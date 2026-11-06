import CoreSpotlight
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// Puts people, moments and quotes into system search, so typing "Emma first steps" on the Home Screen finds the milestone.
///
/// Each item's identifier is its site-relative path (`/profile/7`, `/milestone/45`), which is also what opening it hands `DeepLink.parse(path:)` — the same paths a universal link carries. Only records with a server id are indexed, since only they have a path.
///
/// Incremental: every run builds the whole set from the store, which is cheap, and sends Spotlight only what changed since the last run, keyed by a fingerprint of what each item shows. Interview answers stay out, as they stay out of the widgets.
@MainActor
final class SpotlightIndexer {

    static let shared = SpotlightIndexer()

    /// Whether the account wants its family in system search. On unless turned off in Settings: indexed items show to anyone holding the unlocked phone.
    static let enabledKey = "com.familyrecord.spotlightIndexing"

    private static let fingerprintsKey = "com.familyrecord.spotlightFingerprints"
    private static let domainKey = "com.familyrecord.spotlightDomain"

    private let index: CSSearchableIndex
    private let defaults: UserDefaults

    init(index: CSSearchableIndex = .default(), defaults: UserDefaults = .standard) {
        self.index = index
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// One searchable record, as Spotlight shows it.
    struct Entry: Equatable {
        /// The record's site-relative path, which opening it routes on.
        var id: String
        var title: String
        var text: String
        var date: Date?
        /// A cached thumbnail's photo, when there is one to show.
        var thumbnailRemoteId: Int?

        /// What changing would need Spotlight told again.
        var fingerprint: String {
            [title, text, date.map { String($0.timeIntervalSince1970) } ?? "", thumbnailRemoteId.map(String.init) ?? ""]
                .joined(separator: "\u{1F}")
        }
    }

    /// Everything the store holds that belongs in search.
    static func entries(in context: ModelContext) -> [Entry] {
        var entries: [Entry] = []

        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        for person in people {
            guard let id = person.serverId else { continue }
            let born = person.isPregnancy ? nil : person.birthday
            entries.append(Entry(
                id: "/profile/\(id)",
                title: person.name,
                text: born.map { "Born \($0.displayDay().formatted(date: .long, time: .omitted))" } ?? "",
                date: nil,
                thumbnailRemoteId: person.profilePhotoId
            ))
        }

        let milestones = (try? context.fetch(FetchDescriptor<Milestone>())) ?? []
        for milestone in milestones {
            guard let id = milestone.serverId, milestone.category != .interview, milestone.interviewId == 0 else { continue }
            let who = milestone.person?.name.firstName ?? ""
            let when = milestone.dateText(.long)
            entries.append(Entry(
                id: "/milestone/\(id)",
                title: milestone.displayText,
                text: [who, milestone.category.label, when].filter { !$0.isEmpty }.joined(separator: " · "),
                date: milestone.hasExactDate ? milestone.date : nil,
                thumbnailRemoteId: milestone.photoRemoteIds.first
            ))
        }

        return entries
    }

    /// Brings the index up to date with the store, for the family `domain` names. A different domain than last time — another account — starts from nothing.
    func reindex(context: ModelContext, domain: String) async {
        guard isEnabled else { return }

        if defaults.string(forKey: Self.domainKey) != domain {
            await removeAll()
            defaults.set(domain, forKey: Self.domainKey)
        }

        let current = Self.entries(in: context)
        let previous = defaults.dictionary(forKey: Self.fingerprintsKey) as? [String: String] ?? [:]
        let (changed, removed) = Self.diff(current, against: previous)

        do {
            if !removed.isEmpty {
                try await index.deleteSearchableItems(withIdentifiers: removed)
            }
            if !changed.isEmpty {
                try await index.indexSearchableItems(changed.map { item(for: $0, domain: domain) })
            }
            defaults.set(Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.fingerprint) }), forKey: Self.fingerprintsKey)
            if !changed.isEmpty || !removed.isEmpty {
                AppLog.ui.info("Spotlight: \(changed.count) indexed, \(removed.count) removed")
            }
        } catch {
            // Left as it was: the next run diffs against the last fingerprints that did land, and sends the lot again.
            AppLog.ui.error("Spotlight indexing failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// What to send: entries new or changed since `previous`, and identifiers no longer in the store.
    static func diff(_ current: [Entry], against previous: [String: String]) -> (changed: [Entry], removed: [String]) {
        let changed = current.filter { previous[$0.id] != $0.fingerprint }
        let ids = Set(current.map(\.id))
        let removed = previous.keys.filter { !ids.contains($0) }.sorted()
        return (changed, removed)
    }

    /// Signing out, switching accounts or turning indexing off: nothing of the family stays searchable.
    func removeAll() async {
        defaults.removeObject(forKey: Self.fingerprintsKey)
        defaults.removeObject(forKey: Self.domainKey)
        do {
            try await index.deleteAllSearchableItems()
        } catch {
            AppLog.ui.error("Spotlight removal failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func item(for entry: Entry, domain: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.contentDescription = entry.text.isEmpty ? nil : entry.text
        attributes.contentCreationDate = entry.date
        if let remoteId = entry.thumbnailRemoteId,
           let image = PhotoImageCache.shared.cachedImage(remoteId: remoteId, size: .thumb) {
            attributes.thumbnailData = image.jpegData(compressionQuality: 0.7)
        }
        return CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: domain, attributeSet: attributes)
    }

    /// The family an account's items are filed under.
    static func domain(for user: AuthResponseDTO?) -> String {
        "family-\(user?.familyId ?? 0)"
    }

    /// The destination a tapped Spotlight result names.
    static func link(forActivity activity: NSUserActivity) -> DeepLink? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return DeepLink.parse(path: id)
    }
}

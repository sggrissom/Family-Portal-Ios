import Foundation
import OSLog
import SwiftData

/// Imports what the share extension left in the App Group's inbox, through the same `PhotoImporter` an in-app pick uses, so a share lands in the store and the sync queue exactly as a pick would and shows in the same progress bar.
///
/// Run when the app comes to the foreground and after the sign-in sync, once the people a share names have been pulled. One drain at a time; a request made during one goes round again.
@MainActor
final class ShareInboxDrain {

    static let shared = ShareInboxDrain()

    private let makeInbox: () -> ShareInbox?
    private let resolvePhotoDates: ([URL]) async -> [URL: Date]
    private var running = false
    private var rerunRequested = false

    init(
        makeInbox: @escaping () -> ShareInbox? = { ShareInbox.shared() },
        resolvePhotoDates: @escaping ([URL]) async -> [URL: Date] = { await SharedPhotoDates.resolve($0) }
    ) {
        self.makeInbox = makeInbox
        self.resolvePhotoDates = resolvePhotoDates
    }

    func drain(
        userId: Int,
        access: FamilyAccess,
        addFlow: AddFlow,
        isConnected: Bool,
        context: ModelContext,
        syncService: SyncService?,
        errorPresenter: ErrorPresenter?
    ) async {
        if running {
            rerunRequested = true
            return
        }
        running = true
        defer { running = false }

        repeat {
            rerunRequested = false
            guard let inbox = makeInbox() else { return }
            let shares = inbox.pending()
            guard !shares.isEmpty else { return }

            if shares.contains(where: { $0.manifest.items.contains { $0.kind == .video } }) {
                await addFlow.refreshVideoSupport(isConnected: isConnected)
            }
            for share in shares {
                await importShare(share, from: inbox, userId: userId, access: access, importer: addFlow.importer, context: context, syncService: syncService, errorPresenter: errorPresenter)
            }
        } while rerunRequested
    }

    private func importShare(
        _ share: ShareInbox.Share,
        from inbox: ShareInbox,
        userId: Int,
        access: FamilyAccess,
        importer: PhotoImporter,
        context: ModelContext,
        syncService: SyncService?,
        errorPresenter: ErrorPresenter?
    ) async {
        // Made under another account, which has since signed out: it isn't this one's to add.
        guard share.manifest.ownerUserId == userId else {
            AppLog.ui.info("Dropping a share made by another account")
            inbox.remove(share.folder)
            return
        }

        // A video waits in the inbox until video support is known: offline, or before the server has answered.
        let waiting = importer.videoSupport == nil ? share.manifest.items.filter { $0.kind == .video } : []
        let ready = share.manifest.items.filter { !waiting.contains($0) }
        guard !ready.isEmpty else { return }

        let undatedPhotos = ready.filter { $0.kind == .photo && $0.captureDate == nil }.map { share.url(of: $0) }
        let recoveredDates = undatedPhotos.isEmpty ? [:] : await resolvePhotoDates(undatedPhotos)
        guard !Task.isCancelled else { return }

        let choices = Self.choices(for: share.manifest, access: access, context: context)
        let files = ready.map {
            let url = share.url(of: $0)
            return PhotoImporter.SharedFile(
                url: url, isVideo: $0.kind == .video, captureDate: $0.captureDate ?? recoveredDates[url]
            )
        }
        let outcomes = await importer.importShared(files, choices: choices, into: context, syncService: syncService, errorPresenter: errorPresenter)

        let retry = zip(ready, outcomes).filter { $0.1 == .retryLater }.map(\.0)
        inbox.keep(waiting + retry, of: share)
    }

    /// The manifest's server ids as the importer's choices, keeping only the people and tags this account can still add to.
    static func choices(for manifest: ShareManifest, access: FamilyAccess, context: ModelContext) -> PhotoImporter.BatchChoices {
        let wantedPeople = Set(manifest.personIds)
        let people = ((try? context.fetch(FetchDescriptor<Person>())) ?? [])
            .filter { person in
                guard let id = person.serverId else { return false }
                return wantedPeople.contains(id) && access.canContribute(to: person)
            }

        let wantedTags = Set(manifest.tagIds)
        let tagIds = ((try? context.fetch(FetchDescriptor<FamilyTag>())) ?? [])
            .filter { access.canContribute($0.familyId) }
            .compactMap(\.serverId)
            .filter { wantedTags.contains($0) }

        var choices = PhotoImporter.BatchChoices()
        choices.personIds = Set(people.map(\.id))
        choices.tagRemoteIds = manifest.tagIds.filter { tagIds.contains($0) }
        choices.caption = manifest.caption
        return choices
    }
}

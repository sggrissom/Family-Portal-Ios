import Foundation
import ImageIO
import OSLog
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Where the builder gets a photo's widget-sized JPEG. A protocol so tests can publish without a server.
@MainActor
protocol WidgetImageSource {
    /// JPEG bytes no longer than `maxPixel` on the long edge, or nil when the photo cannot be had right now.
    func widgetImage(for photo: Photo, maxPixel: Int) async -> Data?
}

/// Picks what the widgets show from the store, downsamples the images they need, and writes the lot to `WidgetStore`.
///
/// Everything the widget will want for the next `horizonDays` days is decided here, because the extension cannot ask: it has no network, no keychain and no SwiftData.
@MainActor
struct WidgetSnapshotBuilder {

    let context: ModelContext
    let store: WidgetStore
    let images: any WidgetImageSource

    /// How many days of "On this day" a snapshot carries. Past it the widget falls back to the pool.
    var horizonDays = 14
    /// The pool's make-up. Words cost nothing to carry, so milestones and quotes get room of their own: a Memory widget set to Quotes, or to one child, still has something to turn over.
    var poolPhotos = 30
    var poolMilestones = 15
    var poolQuotes = 15
    /// The fewest pool items each person is in, topped up from their own records when the draw above left them short.
    var poolPerPerson = 6
    /// The most image files a snapshot may name — about 5 MB at `maxPixel`.
    var imageBudget = 80
    /// The long edge of a widget image. The server's `medium` variant is 600 px, which already covers a large widget's mosaic cell at 3×.
    var maxPixel = 600
    /// Per year of a day's "On this day", so thirty years of photos cannot crowd out each other's days.
    var photosPerYear = 4
    var milestonesPerYear = 3
    /// The most quotes the Quote widget carries; text only, so cheap.
    var quoteLimit = 300
    /// The account's own household, listed first on the Family ages widget as on the Home strip.
    var ownFamilyId: Int?
    var calendar = Calendar.current
    var siteURL = AppConstants.defaultServerURL

    /// Where an item not on the server yet opens: Home, since a link can only name a server id.
    static let homeLink = "/dashboard"

    /// The record's own page, as the web names it and `DeepLink` parses it.
    static func link(_ photo: Photo) -> String {
        photo.serverId.map { "/view-photo/\($0)" } ?? homeLink
    }

    static func link(_ milestone: Milestone) -> String {
        milestone.serverId.map { "/milestone/\($0)" } ?? homeLink
    }

    // MARK: - Publishing

    /// Builds and writes a snapshot. `shouldWrite` is asked once more after the images arrive: a sign-out during the downloads must not be followed by the old account's snapshot landing on disk.
    @discardableResult
    func publish(
        ownerUserId: Int,
        now: Date = Date(),
        seed: UInt64 = UInt64.random(in: .min ... .max),
        shouldWrite: () -> Bool = { true }
    ) async -> WidgetSnapshot? {
        let plan = plan(ownerUserId: ownerUserId, now: now, seed: seed)

        var available: [String: String] = [:]
        for request in plan.imageRequests {
            if Task.isCancelled { return nil }
            if store.hasImage(request.fileName) {
                available[request.itemKey] = request.fileName
                continue
            }
            guard let data = await images.widgetImage(for: request.photo, maxPixel: maxPixel) else { continue }
            do {
                try store.writeImage(data, named: request.fileName)
                available[request.itemKey] = request.fileName
            } catch {
                AppLog.widgets.error("Widget image write failed: \(String(describing: error), privacy: .public)")
            }
        }

        let snapshot = plan.resolve(images: available)
        guard !Task.isCancelled, shouldWrite() else { return nil }
        do {
            try store.write(snapshot)
        } catch {
            AppLog.widgets.error("Widget snapshot write failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        store.pruneImages(keeping: snapshot.imageFiles)
        return snapshot
    }

    // MARK: - Choosing

    struct ImageRequest {
        /// The item key the image belongs to — the same photo can illustrate a photo item and an artwork milestone.
        var itemKey: String
        var fileName: String
        var photo: Photo
    }

    /// The snapshot before its images are known: items that would show a picture name the request for one.
    struct Plan {
        var snapshot: WidgetSnapshot
        var imageRequests: [ImageRequest]

        /// Fills in the images that arrived. A photo item without one is dropped — it has nothing else to show — while a milestone keeps its words.
        func resolve(images: [String: String]) -> WidgetSnapshot {
            func fill(_ items: [WidgetItem]) -> [WidgetItem] {
                items.compactMap { item in
                    var item = item
                    item.imageFile = images[item.id]
                    if item.kind == .photo && item.imageFile == nil { return nil }
                    return item
                }
            }
            var resolved = snapshot
            resolved.onThisDay = snapshot.onThisDay
                .mapValues(fill)
                .filter { !$0.value.isEmpty }
            resolved.pool = fill(snapshot.pool)
            return resolved
        }
    }

    func plan(ownerUserId: Int, now: Date, seed: UInt64) -> Plan {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        // Sorted, because a fetch's order is not stable and the pool's seed has to draw the same pool from the same store.
        let photos = ((try? context.fetch(FetchDescriptor<Photo>())) ?? [])
            .filter(Self.canShow)
            .sorted(by: Self.isNewer)
        // Interview answers are left out: "Goldfish crackers" means nothing on a Home Screen without its question, and one interview would crowd the pool with forty of them.
        let milestones = ((try? context.fetch(FetchDescriptor<Milestone>())) ?? [])
            .filter { $0.interviewId == 0 }
            .sorted { ($0.date, Self.itemKey($0)) < ($1.date, Self.itemKey($1)) }

        let photosByRemoteId = Dictionary(
            photos.compactMap { photo in photo.remoteId.flatMap(Int.init).map { ($0, photo) } },
            uniquingKeysWith: { first, _ in first }
        )

        var sources: [String: Photo] = [:]

        func item(_ photo: Photo, yearsAgo: Int?) -> WidgetItem {
            let key = Self.itemKey(photo)
            sources[key] = photo
            return WidgetItem(
                id: key,
                kind: .photo,
                date: photo.photoDate.recordDayKey,
                yearsAgo: yearsAgo,
                title: photo.title,
                personIds: photo.taggedPeople.compactMap(Self.serverId),
                imageFile: nil,
                link: Self.link(photo)
            )
        }

        func item(_ milestone: Milestone, yearsAgo: Int?) -> WidgetItem {
            let key = Self.itemKey(milestone)
            // A milestone illustrated by a photo it carries — artwork above all — shows that photo.
            if let photo = milestone.photoRemoteIds.lazy.compactMap({ photosByRemoteId[$0] }).first {
                sources[key] = photo
            }
            return WidgetItem(
                id: key,
                kind: Self.kind(of: milestone.category),
                date: milestone.date.recordDayKey,
                yearsAgo: yearsAgo,
                title: milestone.displayText,
                personIds: milestone.person.flatMap(Self.serverId).map { [$0] } ?? [],
                imageFile: nil,
                link: Self.link(milestone)
            )
        }

        // MARK: On this day

        var onThisDay: [String: [WidgetItem]] = [:]
        var dayKeys: [String] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = WidgetDay.key(date, calendar: calendar)
            dayKeys.append(key)

            let years = OnThisDay.years(
                on: key,
                photos: photos,
                photoDay: { $0.photoDate.recordDayKey },
                newerPhoto: Self.isNewer,
                milestones: milestones,
                milestoneDay: { $0.date.recordDayKey }
            )
            let items = years.flatMap { year in
                year.photos.prefix(photosPerYear).map { item($0, yearsAgo: year.yearsAgo) }
                    + year.milestones
                        .prefix(milestonesPerYear)
                        .map { item($0, yearsAgo: year.yearsAgo) }
            }
            if !items.isEmpty {
                onThisDay[key] = items
            }
        }

        // MARK: Pool

        var random = SplitMix64(seed: seed)
        let shuffledPhotos = photos.shuffled(using: &random)
        let worded = milestones.filter { !$0.descriptionText.isEmpty }.shuffled(using: &random)
        var drawn: [WidgetItem] = shuffledPhotos.prefix(poolPhotos).map { item($0, yearsAgo: nil) }
            + worded.filter { $0.category != .quote }.prefix(poolMilestones).map { item($0, yearsAgo: nil) }
            + worded.filter { $0.category == .quote }.prefix(poolQuotes).map { item($0, yearsAgo: nil) }

        var inPool = Set(drawn.map(\.id))
        for personId in people.compactMap(Self.serverId) {
            var count = drawn.filter { $0.personIds.contains(personId) }.count
            let theirs = shuffledPhotos.filter { $0.taggedPeople.contains { Self.serverId($0) == personId } }.map { item($0, yearsAgo: nil) }
                + worded.filter { $0.person.flatMap(Self.serverId) == personId }.map { item($0, yearsAgo: nil) }
            for candidate in theirs where count < poolPerPerson && !inPool.contains(candidate.id) {
                drawn.append(candidate)
                inPool.insert(candidate.id)
                count += 1
            }
        }
        let pool = drawn.shuffled(using: &random)

        // MARK: Images, by priority

        // Every day's first few pictures, then the pool's first, then the rest: the budget runs out on the long tail rather than on next week.
        var requests: [ImageRequest] = []
        var requested = Set<String>()
        func request(_ item: WidgetItem) {
            guard requests.count < imageBudget, !requested.contains(item.id), let photo = sources[item.id] else { return }
            requested.insert(item.id)
            requests.append(ImageRequest(itemKey: item.id, fileName: Self.fileName(photo), photo: photo))
        }
        for key in dayKeys {
            for item in (onThisDay[key] ?? []).filter({ sources[$0.id] != nil }).prefix(photosPerYear) { request(item) }
        }
        for item in pool.prefix(imageBudget / 4) { request(item) }
        for key in dayKeys {
            for item in onThisDay[key] ?? [] { request(item) }
        }
        for item in pool { request(item) }

        let widgetPeople = people
            .compactMap { person in Self.serverId(person).map { WidgetPerson(id: $0, name: person.name.firstName) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let quotes = worded.filter { $0.category == .quote }.prefix(quoteLimit).map { item($0, yearsAgo: nil) }

        let snapshot = WidgetSnapshot(
            generatedAt: now,
            ownerUserId: ownerUserId,
            siteURL: siteURL,
            people: widgetPeople,
            onThisDay: onThisDay,
            horizon: dayKeys.last ?? WidgetDay.key(now, calendar: calendar),
            pool: pool,
            quotes: quotes,
            family: family(people, days: dayKeys)
        )
        return Plan(snapshot: snapshot, imageRequests: requests)
    }

    // MARK: - Family ages

    /// The Home strip's people — pregnancies first, then `FamilyGroups.chipOrder` — with each day's age and any birthday ahead. Worked out here because the widget has neither `FamilyStrip` nor the birthdays to run it on.
    func family(_ people: [Person], days: [String]) -> [WidgetFamilyMember] {
        let relations = ((try? context.fetch(FetchDescriptor<PersonRelation>())) ?? []).map(\.edge)
        let ordered = people.filter(\.isPregnancy) + FamilyGroups.chipOrder(people: people, relations: relations, ownFamilyId: ownFamilyId)
        let names = FamilyGroups.chipLabels(ordered)

        return ordered.compactMap { person in
            guard let birthday = person.birthday?.recordDate else { return nil }
            let name = names[person.id] ?? person.name.firstName
            var member = WidgetFamilyMember(personId: Self.serverId(person), name: name, ageByDay: [:])
            for day in days {
                guard let today = Self.recordDate(day) else { continue }
                member.ageByDay[day] = person.isPregnancy
                    ? FamilyStrip.dueSummary(dueDate: birthday, today: today)
                    : FamilyStrip.compactAge(birthday: birthday, today: today)
                if !person.isPregnancy, let ahead = Self.nextBirthday(birthday, from: today),
                   ahead.inDays <= WidgetCopy.birthdayLookaheadDays {
                    member.birthdayByDay[day] = WidgetBirthday(
                        inDays: ahead.inDays,
                        text: WidgetCopy.birthday(name, turning: ahead.turning, inDays: ahead.inDays),
                        turning: ahead.turning
                    )
                }
            }
            return member.ageByDay.values.allSatisfy(\.isEmpty) ? nil : member
        }
    }

    /// Days from `today` to the next birthday, and the age it brings. A 29 February birthday falls on 1 March in a common year, as the server's ages do. Both are record dates.
    static func nextBirthday(_ birthday: Date, from today: Date) -> (inDays: Int, turning: Int)? {
        let born = birthday.recordDay, now = today.recordDay
        guard let bornYear = born.year, let year = now.year, birthday <= today else { return nil }
        for candidateYear in [year, year + 1] {
            guard let date = utc.date(from: DateComponents(year: candidateYear, month: born.month, day: born.day)),
                  date >= today,
                  let days = utc.dateComponents([.day], from: today, to: date).day
            else { continue }
            return (days, candidateYear - bornYear)
        }
        return nil
    }

    private static func recordDate(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    // MARK: - Helpers

    /// A photo can be shown once it is on the server or still holds its own bytes. A video is shown by its poster, but only once it is ready: until then its poster is the server's processing placeholder.
    private static func canShow(_ photo: Photo) -> Bool {
        if photo.isVideo && photo.status != 0 { return false }
        return photo.remoteId != nil || photo.imageData != nil
    }

    /// Newest first by capture time, then by server id — the order of the server's photo index.
    private static func isNewer(_ a: Photo, _ b: Photo) -> Bool {
        if a.photoDate != b.photoDate { return a.photoDate > b.photoDate }
        let left = a.remoteId.flatMap(Int.init) ?? .max, right = b.remoteId.flatMap(Int.init) ?? .max
        return left != right ? left > right : a.id.uuidString > b.id.uuidString
    }

    static func itemKey(_ photo: Photo) -> String {
        "photo:" + (photo.remoteId ?? "local-\(photo.id.uuidString)")
    }

    static func itemKey(_ milestone: Milestone) -> String {
        "milestone:" + (milestone.remoteId ?? "local-\(milestone.id.uuidString)")
    }

    /// Keyed by the photo rather than the item, so a photo shown on five days of a ±2 window is one file, and one already on disk is never fetched again.
    static func fileName(_ photo: Photo) -> String {
        (photo.remoteId ?? "local-\(photo.id.uuidString)") + ".jpg"
    }

    private static func serverId(_ person: Person) -> Int? {
        person.remoteId.flatMap(Int.init)
    }

    private static func kind(of category: MilestoneCategory) -> WidgetItem.Kind {
        switch category {
        case .quote: .quote
        case .artwork: .artwork
        default: .milestone
        }
    }
}

extension WidgetSnapshot {
    /// Every image file the snapshot names; anything else in the directory is left over.
    nonisolated var imageFiles: Set<String> {
        Set((onThisDay.values.flatMap { $0 } + pool).compactMap(\.imageFile))
    }
}

/// A seeded generator, so a test can pin the pool and the app can still draw a fresh one each publish.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - The real image source

/// Local bytes for a photo still uploading, otherwise the server's `medium` variant through `PhotoImageCache` — which answers from its disk cache when the photo has been seen, so a publish on cellular downloads little.
@MainActor
struct CachedWidgetImageSource: WidgetImageSource {
    var cache: PhotoImageCache = .shared

    func widgetImage(for photo: Photo, maxPixel: Int) async -> Data? {
        if let data = photo.imageData {
            return WidgetImageEncoding.downsample(data, maxPixel: maxPixel)
        }
        guard let remoteId = photo.remoteId.flatMap(Int.init) else { return nil }
        guard case .image(let image) = await cache.image(remoteId: remoteId, size: .medium) else { return nil }
        return WidgetImageEncoding.jpeg(image, maxPixel: maxPixel)
    }
}

nonisolated enum WidgetImageEncoding {

    static let quality: CGFloat = 0.8

    /// Decodes no more than it needs: a full-resolution photo straight into a widget extension is what silently fails to render.
    static func downsample(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encode(image)
    }

    static func jpeg(_ image: UIImage, maxPixel: Int) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let longEdge = max(cgImage.width, cgImage.height)
        guard longEdge > maxPixel else { return encode(cgImage) }

        let scale = CGFloat(maxPixel) / CGFloat(longEdge)
        let size = CGSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.cgImage.flatMap(encode)
    }

    private static func encode(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

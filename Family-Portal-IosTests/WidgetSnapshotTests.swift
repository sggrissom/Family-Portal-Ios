import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

// MARK: - The on-this-day rule

@Suite("On this day: the dashboard's rule")
struct OnThisDayRuleTests {

    private struct Record: Equatable {
        var id: Int
        var day: String
        var seconds: Int = 0
    }

    private static func years(on today: String, photos: [Record] = [], milestones: [Record] = []) -> [OnThisDay.Year<Record, Record>] {
        OnThisDay.years(
            on: today,
            photos: photos,
            photoDay: \.day,
            newerPhoto: { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.id > $1.id },
            milestones: milestones,
            milestoneDay: \.day
        )
    }

    @Test("The window is the same day two days either side, inclusive")
    func windowEdges() {
        #expect(OnThisDay.window(around: "2026-10-11", yearsAgo: 1) == [
            "2025-10-09", "2025-10-10", "2025-10-11", "2025-10-12", "2025-10-13",
        ])

        let found = Self.years(on: "2026-10-11", milestones: [
            Record(id: 1, day: "2025-10-08"),
            Record(id: 2, day: "2025-10-09"),
            Record(id: 3, day: "2025-10-13"),
            Record(id: 4, day: "2025-10-14"),
        ])
        #expect(found.map(\.yearsAgo) == [1])
        #expect(found.first?.milestones.map(\.id) == [2, 3])
    }

    @Test("A window crosses a month and a year boundary")
    func windowCrossesYearEnd() {
        #expect(OnThisDay.window(around: "2027-01-01", yearsAgo: 2) == [
            "2024-12-30", "2024-12-31", "2025-01-01", "2025-01-02", "2025-01-03",
        ])
    }

    @Test("One to thirty years back, never this year and never thirty-one")
    func yearLimits() {
        let found = Self.years(on: "2026-10-11", milestones: [
            Record(id: 0, day: "2026-10-11"),
            Record(id: 1, day: "2025-10-11"),
            Record(id: 30, day: "1996-10-11"),
            Record(id: 31, day: "1995-10-11"),
        ])
        #expect(found.map(\.yearsAgo) == [1, 30])
    }

    @Test("29 February moves back to 1 March in a common year, as Go's AddDate does")
    func leapDayNormalisesLikeGo() {
        #expect(OnThisDay.window(around: "2028-02-29", yearsAgo: 1) == [
            "2027-02-27", "2027-02-28", "2027-03-01", "2027-03-02", "2027-03-03",
        ])
        // Four years back is a leap year again, so the day exists.
        #expect(OnThisDay.window(around: "2028-02-29", yearsAgo: 4)[2] == "2024-02-29")
    }

    @Test("At most eight photos a year, newest first")
    func photoCap() {
        let photos = (1...12).map { Record(id: $0, day: "2025-10-1\($0 % 3)", seconds: $0) }
        let found = Self.years(on: "2026-10-11", photos: photos)
        #expect(found.first?.photos.map(\.id) == [12, 11, 10, 9, 8, 7, 6, 5])
    }

    @Test("A year with neither photos nor milestones is left out")
    func emptyYearsDropped() {
        #expect(Self.years(on: "2026-10-11").isEmpty)
        #expect(Self.years(on: "not a day", milestones: [Record(id: 1, day: "2025-10-11")]).isEmpty)
    }
}

// MARK: - The builder

@MainActor
private final class FakeImageSource: WidgetImageSource {
    var unavailable: Set<String> = []
    private(set) var asked: [String] = []

    func widgetImage(for photo: Photo, maxPixel: Int) async -> Data? {
        let key = photo.remoteId ?? photo.id.uuidString
        asked.append(key)
        return unavailable.contains(key) ? nil : Data("jpeg-\(key)".utf8)
    }
}

@MainActor
@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {

    private static func scratchStore() -> WidgetStore {
        WidgetStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetTests.\(UUID().uuidString)", isDirectory: true))
    }

    /// 11 October 2026, noon in UTC — the builder's "today" when the calendar is UTC.
    private static let now = Date(timeIntervalSince1970: 1_791_720_000)

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func day(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 9))!
    }

    private struct Fixture {
        let context: ModelContext
        let store: WidgetStore
        let images: FakeImageSource
        let clara: Person

        func builder() -> WidgetSnapshotBuilder {
            var builder = WidgetSnapshotBuilder(context: context, store: store, images: images)
            builder.calendar = WidgetSnapshotBuilderTests.utc
            builder.siteURL = "https://example.test"
            return builder
        }

        @discardableResult
        func photo(_ remoteId: String?, on day: String, bytes: Data? = nil, tagged: Bool = true) -> Photo {
            let photo = Photo(title: "", descriptionText: "", photoDate: WidgetSnapshotBuilderTests.day(day), imageData: bytes)
            photo.remoteId = remoteId
            context.insert(photo)
            if tagged { photo.taggedPeople = [clara] }
            return photo
        }

        @discardableResult
        func milestone(_ remoteId: String, _ text: String, on day: String, category: MilestoneCategory = .first, photos: [Int] = []) -> Milestone {
            let milestone = Milestone(descriptionText: text, category: category, date: WidgetSnapshotBuilderTests.day(day).recordDate)
            milestone.remoteId = remoteId
            milestone.person = clara
            milestone.photoRemoteIds = photos
            context.insert(milestone)
            return milestone
        }
    }

    private static func fixture() throws -> Fixture {
        let context = try TestStore.makeContext()
        let clara = Person(name: "Clara Grissom", gender: .female)
        clara.remoteId = "7"
        context.insert(clara)
        let offline = Person(name: "Offline", gender: .other)
        context.insert(offline)
        return Fixture(context: context, store: scratchStore(), images: FakeImageSource(), clara: clara)
    }

    @Test("Today's on-this-day items carry their years, first names and images")
    func todaysItems() async throws {
        let fixture = try Self.fixture()
        fixture.photo("101", on: "2024-10-12")
        fixture.milestone("55", "First steps", on: "2025-10-10")
        fixture.milestone("56", "Bye bye moon", on: "2025-10-11", category: .quote)

        let snapshot = try #require(await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1))

        #expect(snapshot.ownerUserId == 3)
        #expect(snapshot.people == [WidgetPerson(id: 7, name: "Clara")])
        let today = try #require(snapshot.onThisDay["2026-10-11"])
        #expect(today.map(\.id) == ["milestone:55", "milestone:56", "photo:101"])
        #expect(today.map(\.yearsAgo) == [1, 1, 2])
        #expect(today[1].kind == .quote)
        #expect(today[1].title == "“Bye bye moon”")
        #expect(today[2].imageFile == "101.jpg")
        #expect(today[2].personIds == [7])
        #expect(today.map(\.link) == ["/milestone/55", "/milestone/56", "/view-photo/101"])
        #expect(snapshot.url(for: today[2])?.absoluteString == "https://example.test/view-photo/101")

        #expect(fixture.store.read() == snapshot)
        #expect(fixture.store.hasImage("101.jpg"))
    }

    @Test("Fourteen days of on-this-day, each with its own window")
    func horizon() async throws {
        let fixture = try Self.fixture()
        // In the window of 22–24 October only.
        fixture.milestone("60", "Lost a tooth", on: "2025-10-24")

        let snapshot = try #require(await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1))

        #expect(snapshot.horizon == "2026-10-24")
        #expect(snapshot.onThisDay.keys.sorted() == ["2026-10-22", "2026-10-23", "2026-10-24"])
    }

    @Test("A photo whose image cannot be had is dropped; a milestone keeps its words")
    func unavailableImages() async throws {
        let fixture = try Self.fixture()
        fixture.photo("101", on: "2025-10-11")
        fixture.milestone("55", "First steps", on: "2025-10-11", photos: [101])
        fixture.images.unavailable = ["101"]

        let snapshot = try #require(await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1))

        let today = try #require(snapshot.onThisDay["2026-10-11"])
        #expect(today.map(\.id) == ["milestone:55"])
        #expect(today[0].imageFile == nil)
        #expect(snapshot.pool.contains { $0.kind == .photo } == false)
    }

    @Test("A milestone carrying a photo shows that photo")
    func milestoneIllustratedByItsPhoto() async throws {
        let fixture = try Self.fixture()
        fixture.photo("101", on: "2019-01-01")
        fixture.milestone("55", "Rainbow", on: "2025-10-11", category: .artwork, photos: [101])

        let snapshot = try #require(await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1))

        let artwork = try #require(snapshot.onThisDay["2026-10-11"]?.first)
        #expect(artwork.kind == .artwork)
        #expect(artwork.imageFile == "101.jpg")
    }

    @Test("A photo still uploading is shown from its own bytes; photos with neither are left out")
    func localPhotos() async throws {
        let fixture = try Self.fixture()
        let pending = fixture.photo(nil, on: "2025-10-11", bytes: Data("raw".utf8))
        fixture.photo(nil, on: "2025-10-11")

        let snapshot = try #require(await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1))

        let today = try #require(snapshot.onThisDay["2026-10-11"])
        #expect(today.map(\.id) == ["photo:local-\(pending.id.uuidString)"])
        // No server id to name, so a tap opens Home.
        #expect(today[0].link == "/dashboard")
        #expect(today[0].imageFile == "local-\(pending.id.uuidString).jpg")
    }

    @Test("An image already on disk is reused rather than fetched again")
    func reusesImages() async throws {
        let fixture = try Self.fixture()
        fixture.photo("101", on: "2025-10-11")
        try fixture.store.writeImage(Data("old".utf8), named: "101.jpg")

        _ = await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1)

        #expect(fixture.images.asked.isEmpty)
    }

    @Test("Images the new snapshot no longer names are pruned")
    func prunes() async throws {
        let fixture = try Self.fixture()
        fixture.photo("101", on: "2025-10-11")
        try fixture.store.writeImage(Data("stale".utf8), named: "999.jpg")

        let snapshot = try #require(await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1))

        #expect(snapshot.imageFiles == ["101.jpg"])
        #expect(fixture.store.hasImage("999.jpg") == false)
        #expect(fixture.store.hasImage("101.jpg"))
    }

    @Test("The image budget caps the files, nearest days first")
    func imageBudget() async throws {
        let fixture = try Self.fixture()
        for year in 1...6 {
            fixture.photo("\(year)", on: "\(2026 - year)-10-11")
        }
        fixture.photo("90", on: "2025-10-20")
        var builder = fixture.builder()
        builder.imageBudget = 3
        builder.poolPhotos = 0
        builder.poolPerPerson = 0

        let snapshot = try #require(await builder.publish(ownerUserId: 3, now: Self.now, seed: 1))

        #expect(snapshot.imageFiles == ["1.jpg", "2.jpg", "3.jpg"])
        #expect(fixture.images.asked == ["1", "2", "3"])
    }

    @Test("The pool draws photos, milestones and quotes apart, and the same seed draws the same pool")
    func pool() async throws {
        let fixture = try Self.fixture()
        for index in 1...10 {
            fixture.photo("\(index)", on: "2020-0\(index % 9 + 1)-01")
            fixture.milestone("\(100 + index)", "Milestone \(index)", on: "2019-0\(index % 9 + 1)-01")
            fixture.milestone("\(200 + index)", "Quote \(index)", on: "2018-0\(index % 9 + 1)-01", category: .quote)
        }
        var builder = fixture.builder()
        builder.poolPhotos = 4
        builder.poolMilestones = 3
        builder.poolQuotes = 2

        let first = builder.plan(ownerUserId: 3, now: Self.now, seed: 42).snapshot.pool
        let again = builder.plan(ownerUserId: 3, now: Self.now, seed: 42).snapshot.pool

        #expect(first.count == 9)
        #expect(first.filter { $0.kind == .photo }.count == 4)
        #expect(first.filter { $0.kind == .milestone }.count == 3)
        #expect(first.filter { $0.kind == .quote }.count == 2)
        #expect(first == again)
        #expect(first.allSatisfy { $0.yearsAgo == nil })
    }

    @Test("Someone the draw left out is topped up from their own records")
    func poolPerPerson() async throws {
        let fixture = try Self.fixture()
        let theo = Person(name: "Theo", gender: .male)
        theo.remoteId = "8"
        fixture.context.insert(theo)
        for index in 1...10 {
            fixture.photo("\(index)", on: "2020-0\(index % 9 + 1)-01")
        }
        for index in 1...4 {
            let milestone = fixture.milestone("\(300 + index)", "Theo \(index)", on: "2021-01-0\(index)")
            milestone.person = theo
        }
        var builder = fixture.builder()
        builder.poolPhotos = 5
        builder.poolMilestones = 0
        builder.poolPerPerson = 3

        let pool = builder.plan(ownerUserId: 3, now: Self.now, seed: 7).snapshot.pool

        #expect(pool.filter { $0.personIds == [8] }.count == 3)
        #expect(pool.filter { $0.personIds == [7] }.count == 5)
    }

    @Test("A run told not to write leaves the store alone")
    func refusesToWrite() async throws {
        let fixture = try Self.fixture()
        fixture.milestone("55", "First steps", on: "2025-10-11")

        let snapshot = await fixture.builder().publish(ownerUserId: 3, now: Self.now, seed: 1, shouldWrite: { false })

        #expect(snapshot == nil)
        #expect(fixture.store.read() == nil)
    }
}

// MARK: - The store

@Suite("Widget store")
struct WidgetStoreTests {

    private static func scratch() -> WidgetStore {
        WidgetStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetStoreTests.\(UUID().uuidString)", isDirectory: true))
    }

    private static func snapshot(version: Int = WidgetSnapshot.currentVersion) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000_000), ownerUserId: 1, siteURL: "https://x.test",
            people: [], onThisDay: [:], horizon: "2026-10-24", pool: []
        )
        snapshot.version = version
        return snapshot
    }

    @Test("A snapshot round-trips")
    func roundTrip() throws {
        let store = Self.scratch()
        try store.write(Self.snapshot())
        #expect(store.read() == Self.snapshot())
    }

    @Test("A snapshot of another version reads as none")
    func otherVersion() throws {
        let store = Self.scratch()
        try store.write(Self.snapshot(version: WidgetSnapshot.currentVersion + 1))
        #expect(store.read() == nil)
    }

    @Test("Removing the store takes the images with it")
    func removeAll() throws {
        let store = Self.scratch()
        try store.write(Self.snapshot())
        try store.writeImage(Data([1]), named: "1.jpg")

        store.removeAll()

        #expect(store.read() == nil)
        #expect(store.hasImage("1.jpg") == false)
        #expect(FileManager.default.fileExists(atPath: store.directory.path) == false)
    }
}

// MARK: - Publishing and signing out

@MainActor
@Suite("Widget publisher")
struct WidgetPublisherTests {

    private static func scratchDefaults() -> UserDefaults {
        let name = "WidgetPublisherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func publisher(store: WidgetStore, reloads: @escaping () -> Void = {}) -> WidgetPublisher {
        WidgetPublisher(makeStore: { store }, images: FakeImageSource(), defaults: scratchDefaults(), reloadTimelines: reloads)
    }

    private static func scratchStore() -> WidgetStore {
        WidgetStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetPublisherTests.\(UUID().uuidString)", isDirectory: true))
    }

    @Test("Publishing writes a snapshot and reloads the widgets")
    func publishes() async throws {
        let store = Self.scratchStore()
        var reloads = 0
        let publisher = Self.publisher(store: store) { reloads += 1 }

        await publisher.publish(context: try TestStore.makeContext(), ownerUserId: 9)

        #expect(store.read()?.ownerUserId == 9)
        #expect(reloads == 1)
        #expect(publisher.lastPublished != nil)
    }

    @Test("A recent snapshot is not rebuilt on the way to the background")
    func staleOnly() async throws {
        let store = Self.scratchStore()
        var reloads = 0
        let publisher = Self.publisher(store: store) { reloads += 1 }
        let context = try TestStore.makeContext()

        await publisher.publish(context: context, ownerUserId: 9)
        await publisher.publishIfStale(context: context, ownerUserId: 9)
        #expect(reloads == 1)

        await publisher.publishIfStale(context: context, ownerUserId: 9, now: Date().addingTimeInterval(7 * 3600))
        #expect(reloads == 2)
    }

    @Test("Clearing deletes the snapshot and redraws the widgets signed out")
    func clears() async throws {
        let store = Self.scratchStore()
        var reloads = 0
        let publisher = Self.publisher(store: store) { reloads += 1 }
        await publisher.publish(context: try TestStore.makeContext(), ownerUserId: 9)

        publisher.clear()

        #expect(store.read() == nil)
        #expect(reloads == 2)
        #expect(publisher.lastPublished == nil)
    }

    @Test("A full local erase signs the widgets out")
    func eraseClearsWidgets() async throws {
        let store = Self.scratchStore()
        let publisher = Self.publisher(store: store)
        let context = try TestStore.makeContext()
        await publisher.publish(context: context, ownerUserId: 9)

        await LocalDataReset.erase(
            .everything,
            context: context,
            syncQueue: TestStore.makeQueue(),
            activityCache: ActivitySnapshotCache(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("WidgetEraseTests.\(UUID().uuidString)", isDirectory: true)),
            photoCache: PhotoImageCache(session: URLSession(configuration: .ephemeral)),
            widgets: publisher
        )

        #expect(store.read() == nil)
    }
}

// MARK: - The timeline

@Suite("Widget timeline")
struct WidgetTimelineTests {

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func at(_ day: String, hour: Int, minute: Int = 0) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute))!
    }

    private static func item(_ id: String, image: Bool, years: Int? = 1, title: String = "") -> WidgetItem {
        WidgetItem(id: id, kind: image ? .photo : .milestone, date: "2025-10-11", yearsAgo: years, title: title,
                   personIds: [7], imageFile: image ? "\(id).jpg" : nil, link: "/dashboard")
    }

    private static func snapshot(onThisDay: [String: [WidgetItem]] = [:], pool: [WidgetItem] = []) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: Date(), ownerUserId: 1, siteURL: "https://x.test",
                       people: [WidgetPerson(id: 7, name: "Clara")], onThisDay: onThisDay,
                       horizon: "2026-10-24", pool: pool)
    }

    @Test("Entries start now and land on every three-hour boundary")
    func entryDates() {
        let now = Self.at("2026-10-11", hour: 13, minute: 20)
        let dates = WidgetTimeline.entryDates(from: now, hours: 12, calendar: Self.utc)
        #expect(dates == [
            now,
            Self.at("2026-10-11", hour: 15),
            Self.at("2026-10-11", hour: 18),
            Self.at("2026-10-11", hour: 21),
            Self.at("2026-10-12", hour: 0),
        ])
    }

    @Test("Pictures take turns through the day; words follow the featured one")
    func featuring() {
        let items = [Self.item("m", image: false), Self.item("a", image: true), Self.item("b", image: true)]
        #expect(WidgetTimeline.featuring(items, slot: 0).map(\.id) == ["a", "m", "b"])
        #expect(WidgetTimeline.featuring(items, slot: 1).map(\.id) == ["b", "m", "a"])
        #expect(WidgetTimeline.featuring(items, slot: 2).map(\.id) == ["a", "m", "b"])
        #expect(WidgetTimeline.featuring([Self.item("m", image: false)], slot: 3).map(\.id) == ["m"])
    }

    @Test("A day with on-this-day items shows them")
    func onThisDay() {
        let snapshot = Self.snapshot(onThisDay: ["2026-10-11": [Self.item("a", image: true)]], pool: [Self.item("p", image: true)])
        let moment = WidgetTimeline.onThisDay(snapshot, at: Self.at("2026-10-11", hour: 8), calendar: Self.utc)
        #expect(moment.source == .onThisDay)
        #expect(moment.featured?.id == "a")
        #expect(moment.names(for: moment.featured!) == ["Clara"])
        #expect(moment.isStale == false)
    }

    @Test("A day with nothing falls back to the pool, walking it slot by slot")
    func memoryFallback() {
        let pool = [Self.item("p0", image: true, years: nil), Self.item("p1", image: true, years: nil)]
        let snapshot = Self.snapshot(pool: pool)
        let first = WidgetTimeline.onThisDay(snapshot, at: Self.at("2026-10-12", hour: 1), calendar: Self.utc)
        let next = WidgetTimeline.onThisDay(snapshot, at: Self.at("2026-10-12", hour: 4), calendar: Self.utc)
        #expect(first.source == .memory)
        #expect(first.items.count == 1)
        #expect(first.featured?.id != next.featured?.id)
    }

    @Test("Past the horizon the moment is stale")
    func stale() {
        let snapshot = Self.snapshot(pool: [Self.item("p", image: true, years: nil)])
        #expect(WidgetTimeline.onThisDay(snapshot, at: Self.at("2026-10-24", hour: 12), calendar: Self.utc).isStale == false)
        #expect(WidgetTimeline.onThisDay(snapshot, at: Self.at("2026-10-25", hour: 0), calendar: Self.utc).isStale)
    }

    @Test("No snapshot is signed out; an empty one has nothing")
    func emptyStates() {
        #expect(WidgetTimeline.onThisDay(nil, at: Date()).source == .signedOut)
        #expect(WidgetTimeline.onThisDay(Self.snapshot(), at: Date()).source == .nothing)
    }

    @Test("Only the anniversary itself says On this day; nearby days name their date; memories make no claim")
    func dating() {
        let snapshot = Self.snapshot(onThisDay: ["2026-10-11": [
            WidgetItem(id: "exact", kind: .milestone, date: "2023-10-11", yearsAgo: 3, title: "x", personIds: [7], link: "/"),
            WidgetItem(id: "near", kind: .milestone, date: "2024-10-13", yearsAgo: 2, title: "y", personIds: [7], link: "/"),
        ]])
        let moment = WidgetTimeline.onThisDay(snapshot, at: Self.at("2026-10-11", hour: 8), calendar: Self.utc)
        #expect(moment.day == "2026-10-11")
        #expect(moment.dating(moment.items[0]) == .anniversary(yearsAgo: 3))
        #expect(moment.dating(moment.items[1]) == .nearby("2024-10-13"))
        #expect(moment.dating(moment.items[1]).label == WidgetCopy.aroundThisDay)

        let memory = WidgetMoment(source: .memory, items: [Self.item("m", image: false, years: nil)], day: "2026-10-11")
        #expect(memory.dating(memory.items[0]) == .memory("2025-10-11"))
        #expect(memory.dating(memory.items[0]).label == WidgetCopy.memory)
        #expect(memory.dating(memory.items[0]).compact == "A memory · 2025")
    }

    @Test("A 29 February record has its anniversary on 1 March in a common year", arguments: [
        ("2024-02-29", "2027-03-01", true),
        ("2024-02-29", "2027-02-28", false),
        ("2024-02-29", "2028-02-29", true),
        ("2024-02-29", "2028-03-01", false),
        ("2023-10-11", "2026-10-11", true),
        ("2023-10-11", "2026-10-12", false),
    ])
    func anniversary(record: String, day: String, expected: Bool) {
        #expect(WidgetDay.isAnniversary(of: record, on: day) == expected)
    }

    @Test("A record's date reads as a calendar day, whatever the time zone")
    func formattedDate() {
        #expect(WidgetCopy.date("2024-10-13", locale: Locale(identifier: "en_US")) == "Oct 13, 2024")
        #expect(WidgetCopy.attribution(["Clara"], "3 years ago") == "Clara · 3 years ago")
        #expect(WidgetCopy.attribution([], "3 years ago") == "3 years ago")
    }

    @Test("Stored quotation marks are recognised, so no decorative pair is added")
    func quoted() {
        #expect(WidgetCopy.isQuoted("“Bye bye moon”"))
        #expect(!WidgetCopy.isQuoted("Bye bye moon"))
        #expect(!WidgetCopy.isQuoted(""))
    }

    @Test("A photo whose image cannot be drawn is left out; a milestone keeps its words")
    func missingImages() {
        let day = [
            Self.item("gone", image: true),
            WidgetItem(id: "art", kind: .artwork, date: "2025-10-11", yearsAgo: 1, title: "Drawing", personIds: [7], imageFile: "art.jpg", link: "/"),
            Self.item("ok", image: true),
        ]
        let snapshot = Self.snapshot(onThisDay: ["2026-10-11": day])
        let available: (String) -> Bool = { $0 == "ok.jpg" }
        let moment = WidgetTimeline.onThisDay(snapshot, at: Self.at("2026-10-11", hour: 1), calendar: Self.utc, imageAvailable: available)
        #expect(moment.items.map(\.id) == ["ok", "art"])
        #expect(moment.items.first { $0.id == "art" }?.hasImage == false)
        #expect(moment.pictures.map(\.id) == ["ok"])
        #expect(moment.textRecords.map(\.id) == ["art"])

        // Nothing drawable that day: the pool's untitled photo is not chosen either.
        let fallback = Self.snapshot(onThisDay: ["2026-10-11": [Self.item("gone", image: true)]],
                                     pool: [Self.item("gone2", image: true, years: nil), Self.item("words", image: false, years: nil, title: "Words")])
        let memory = WidgetTimeline.onThisDay(fallback, at: Self.at("2026-10-11", hour: 1), calendar: Self.utc, imageAvailable: { _ in false })
        #expect(memory.source == .memory)
        #expect(memory.featured?.id == "words")
    }

    @Test("Shuffle is offered only when the usable pool has somewhere to go")
    func shuffleNeedsTwo() {
        let pool = [Self.item("a", image: true, years: nil), Self.item("b", image: true, years: nil)]
        let snapshot = Self.snapshot(pool: pool)
        let both = WidgetTimeline.memory(snapshot, at: Date(), filter: MemoryFilter(), rotationHours: 6)
        #expect(both.poolSize == 2)
        #expect(both.canShuffle)
        let one = WidgetTimeline.memory(snapshot, at: Date(), filter: MemoryFilter(), rotationHours: 6, imageAvailable: { $0 == "a.jpg" })
        #expect(one.poolSize == 1)
        #expect(one.featured?.id == "a")
        #expect(!one.canShuffle)
    }
}

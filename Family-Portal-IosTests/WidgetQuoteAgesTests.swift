import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Quote and Family ages widgets")
struct WidgetQuoteAgesTests {

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func day(_ key: String, hour: Int = 0) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    /// 11 October 2026, noon UTC.
    private static let now = day("2026-10-11", hour: 12)

    private static func builder(_ context: ModelContext) -> WidgetSnapshotBuilder {
        var builder = WidgetSnapshotBuilder(
            context: context,
            store: WidgetStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("WidgetQuoteAgesTests.\(UUID().uuidString)", isDirectory: true)),
            images: NoImages()
        )
        builder.calendar = Self.utc
        return builder
    }

    private final class NoImages: WidgetImageSource {
        func widgetImage(for photo: Photo, maxPixel: Int) async -> Data? { nil }
    }

    // MARK: - Birthdays

    @Test("The next birthday, and the age it brings", arguments: [
        ("2026-10-08", 3, 4),
        ("2026-10-11", 0, 4),
        ("2026-10-12", 364, 5),
    ])
    func nextBirthday(today: String, inDays: Int, turning: Int) throws {
        let next = try #require(WidgetSnapshotBuilder.nextBirthday(Self.day("2022-10-11"), from: Self.day(today)))
        #expect(next.inDays == inDays)
        #expect(next.turning == turning)
    }

    @Test("A 29 February birthday falls on 1 March in a common year")
    func leapDayBirthday() throws {
        let next = try #require(WidgetSnapshotBuilder.nextBirthday(Self.day("2024-02-29"), from: Self.day("2027-02-27")))
        #expect(next.inDays == 2)
        #expect(next.turning == 3)
    }

    @Test("Nobody has a birthday before they are born")
    func unbornHasNoBirthday() {
        #expect(WidgetSnapshotBuilder.nextBirthday(Self.day("2027-01-01"), from: Self.day("2026-10-11")) == nil)
    }

    // MARK: - The snapshot

    @Test("Each day carries every age, pregnancies first, and birthdays close enough to mention")
    func familyAges() throws {
        let context = try TestStore.makeContext()
        let clara = Person(name: "Clara Grissom", gender: .female, birthday: Self.day("2023-06-01"))
        clara.remoteId = "7"
        let theo = Person(name: "Theo", gender: .male, birthday: Self.day("2025-10-20"))
        theo.remoteId = "8"
        let baby = Person(name: "Baby", gender: .other, birthday: Self.day("2026-12-01"), isPregnancy: true)
        let nobody = Person(name: "No Birthday", gender: .other)
        [clara, theo, baby, nobody].forEach(context.insert)

        let snapshot = Self.builder(context).plan(ownerUserId: 1, now: Self.now, seed: 1).snapshot
        let family = try #require(snapshot.family)

        #expect(family.map(\.name).first == "Baby")
        #expect(Set(family.map(\.name)) == ["Baby", "Clara", "Theo"])
        let theoAges = try #require(family.first { $0.name == "Theo" })
        #expect(theoAges.personId == 8)
        #expect(theoAges.ageByDay["2026-10-11"] == "11m")
        // Months until two, as on the Home strip.
        #expect(theoAges.ageByDay["2026-10-20"] == "12m")
        #expect(theoAges.ageByDay.count == 14)
        #expect(theoAges.birthdayByDay["2026-10-11"] == WidgetBirthday(inDays: 9, text: "Theo turns 1 in 9 days"))
        #expect(theoAges.birthdayByDay["2026-10-20"]?.text == "Theo turns 1 today")
        #expect(theoAges.birthdayByDay["2026-10-21"] == nil)
        #expect(family.first { $0.name == "Baby" }?.ageByDay["2026-10-11"] == "Due in 7w 2d")
        #expect(family.first { $0.name == "Baby" }?.birthdayByDay.isEmpty == true)
        #expect(family.first { $0.name == "Clara" }?.ageByDay["2026-10-11"] == "3y 4m")
    }

    @Test("Every quote is carried, not just the pool's share")
    func quotes() throws {
        let context = try TestStore.makeContext()
        for index in 1...20 {
            let quote = Milestone(descriptionText: "Quote \(index)", category: .quote, date: Self.day("2024-01-01"))
            quote.remoteId = "\(index)"
            context.insert(quote)
        }
        var builder = Self.builder(context)
        builder.poolQuotes = 3

        let snapshot = builder.plan(ownerUserId: 1, now: Self.now, seed: 1).snapshot

        #expect(snapshot.quotes?.count == 20)
        #expect(snapshot.pool.filter { $0.kind == .quote }.count == 3)
    }

    // MARK: - The widgets' reading of it

    private static func snapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now, ownerUserId: 1, siteURL: "https://x.test",
            people: [WidgetPerson(id: 7, name: "Clara")], onThisDay: [:], horizon: "2026-10-24",
            pool: [WidgetItem(id: "q-pool", kind: .quote, date: "2024-01-01", title: "pool", personIds: [7], link: "/")],
            quotes: [
                WidgetItem(id: "q1", kind: .quote, date: "2024-01-01", title: "one", personIds: [7], link: "/"),
                WidgetItem(id: "q2", kind: .quote, date: "2024-01-01", title: "two", personIds: [8], link: "/"),
            ],
            family: [
                WidgetFamilyMember(personId: 7, name: "Clara", ageByDay: ["2026-10-11": "3y 4m"],
                                   birthdayByDay: ["2026-10-11": WidgetBirthday(inDays: 9, text: "Clara later")]),
                WidgetFamilyMember(personId: 8, name: "Theo", ageByDay: ["2026-10-11": "11m"],
                                   birthdayByDay: ["2026-10-11": WidgetBirthday(inDays: 2, text: "Theo sooner")]),
            ]
        )
    }

    @Test("The Quote widget reads every quote, filtered by person")
    func quoteWidget() {
        let all = (0..<4).compactMap { WidgetTimeline.quote(Self.snapshot(), at: Self.day("2026-10-11", hour: $0 * 3), calendar: Self.utc).featured?.id }
        #expect(Set(all) == ["q1", "q2"])
        #expect(WidgetTimeline.quote(Self.snapshot(), at: Self.now, personId: 8, calendar: Self.utc).featured?.id == "q2")
        #expect(WidgetTimeline.quote(Self.snapshot(), at: Self.now, personId: 99).source == .nothing)
    }

    @Test("Family ages for the day, soonest birthday first, and for one person")
    func agesWidget() throws {
        let ages = try #require(WidgetTimeline.ages(Self.snapshot(), at: Self.day("2026-10-11", hour: 8), calendar: Self.utc))
        #expect(ages.rows == [FamilyAges.Row(name: "Clara", age: "3y 4m"), FamilyAges.Row(name: "Theo", age: "11m")])
        #expect(ages.birthdays == ["Theo sooner", "Clara later"])

        let theo = try #require(WidgetTimeline.ages(Self.snapshot(), at: Self.day("2026-10-11"), personId: 8, calendar: Self.utc))
        #expect(theo.rows.map(\.name) == ["Theo"])

        let late = try #require(WidgetTimeline.ages(Self.snapshot(), at: Self.day("2026-10-30"), calendar: Self.utc))
        #expect(late.rows.isEmpty)
        #expect(late.isStale)
        #expect(WidgetTimeline.ages(nil, at: Self.now) == nil)
    }
}

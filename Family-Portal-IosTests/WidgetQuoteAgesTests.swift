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
        #expect(theoAges.birthdayByDay["2026-10-11"] == WidgetBirthday(inDays: 9, text: "Theo turns 1 in 9 days", turning: 1))
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
            people: [WidgetPerson(id: 7, name: "Clara"), WidgetPerson(id: 8, name: "Theo"), WidgetPerson(id: 9, name: "Ruth")],
            onThisDay: [:], horizon: "2026-10-24",
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
        #expect(ages.rows.map(\.name) == ["Clara", "Theo"])
        #expect(ages.rows.map(\.age) == ["3y 4m", "11m"])
        #expect(ages.rows.map(\.id) == ["person:7", "person:8"])
        #expect(ages.birthdays.map(\.text) == ["Theo sooner", "Clara later"])

        let theo = try #require(WidgetTimeline.ages(Self.snapshot(), at: Self.day("2026-10-11"), personIds: [8], calendar: Self.utc))
        #expect(theo.rows.map(\.name) == ["Theo"])

        let late = try #require(WidgetTimeline.ages(Self.snapshot(), at: Self.day("2026-10-30"), calendar: Self.utc))
        #expect(late.rows.isEmpty)
        #expect(late.birthdays.isEmpty)
        #expect(late.isStale)
        #expect(WidgetTimeline.ages(nil, at: Self.now) == nil)
    }

    @Test("Chosen people keep the family's order, and one with no age is shown as such rather than dropped")
    func chosenPeople() throws {
        let ages = try #require(WidgetTimeline.ages(Self.snapshot(), at: Self.day("2026-10-11"), personIds: [9, 8, 7], calendar: Self.utc))
        #expect(ages.rows.map(\.name) == ["Clara", "Theo", "Ruth"])
        #expect(ages.rows.last?.age == nil)
        // A chosen id the snapshot does not know at all (removed since) has no name to show.
        let gone = try #require(WidgetTimeline.ages(Self.snapshot(), at: Self.day("2026-10-11"), personIds: [7, 99], calendar: Self.utc))
        #expect(gone.rows.map(\.name) == ["Clara"])
    }

    @Test("People take precedence over Person, and nothing chosen is the whole family")
    func precedence() {
        #expect(WidgetTimeline.familySelection(people: nil, person: nil) == [])
        #expect(WidgetTimeline.familySelection(people: [], person: 7) == [7])
        #expect(WidgetTimeline.familySelection(people: [8, 9], person: 7) == [8, 9])
    }

    private static func family(_ count: Int) -> WidgetSnapshot {
        var snapshot = snapshot()
        snapshot.family = (0..<count).map { index in
            WidgetFamilyMember(personId: 100 + index, name: "Person \(index)", ageByDay: ["2026-10-11": "\(index)y", "2026-10-12": "\(index)y"])
        }
        return snapshot
    }

    @Test("The overview counts everyone it leaves out", arguments: [
        (0, 6, 0, 0), (1, 6, 1, 0), (4, 6, 4, 0), (6, 6, 6, 0), (7, 6, 5, 2), (8, 8, 8, 0), (10, 6, 5, 5), (10, 8, 7, 3),
    ])
    func overview(people: Int, capacity: Int, shown: Int, more: Int) throws {
        let ages = try #require(WidgetTimeline.ages(Self.family(people), at: Self.day("2026-10-11"), calendar: Self.utc))
        let overview = ages.overview(capacity: capacity)
        #expect(overview.shown.count == shown)
        #expect(overview.more == more)
        #expect(overview.shown.count + overview.more == people)
    }

    @Test("The spotlight reaches everyone with an age, one a day")
    func spotlight() throws {
        let snapshot = Self.family(4)
        var seen: [String] = []
        for offset in 0..<4 {
            let date = Self.day("2026-10-11").addingTimeInterval(TimeInterval(offset) * 86_400)
            var extended = snapshot
            extended.family = snapshot.family?.map { member in
                var member = member
                member.ageByDay[WidgetDay.key(date, calendar: Self.utc)] = "1y"
                return member
            }
            extended.horizon = "2026-12-31"
            let ages = try #require(WidgetTimeline.ages(extended, at: date, calendar: Self.utc))
            seen.append(try #require(ages.spotlight?.name))
        }
        #expect(Set(seen).count == 4)
    }

    @Test("Birthdays on the same day are kept together, in family order")
    func sameDayBirthdays() throws {
        var snapshot = Self.snapshot()
        snapshot.family = ["Ann", "Bea", "Cal"].enumerated().map { index, name in
            WidgetFamilyMember(personId: 200 + index, name: name, ageByDay: ["2026-10-11": "1y"],
                               birthdayByDay: ["2026-10-11": WidgetBirthday(inDays: index == 2 ? 6 : 3, text: name, turning: 2)])
        }
        let ages = try #require(WidgetTimeline.ages(snapshot, at: Self.day("2026-10-11"), calendar: Self.utc))
        #expect(ages.nextBirthdays.map(\.name) == ["Ann", "Bea"])
        #expect(ages.birthdays.map(\.name) == ["Ann", "Bea", "Cal"])
        #expect(ages.birthdays.first?.turning == 2)
        #expect(WidgetCopy.sharedBirthday(["Ann", "Bea"], inDays: 3) == "Ann & Bea: birthdays in 3 days")
    }

    @Test("Birthday words keep the age and the countdown", arguments: [(0, "Today"), (1, "Tomorrow"), (4, "In 4 days")])
    func countdown(days: Int, expected: String) {
        #expect(WidgetCopy.countdown(days) == expected)
        #expect(WidgetCopy.turns(12) == "Turns 12")
        #expect(WidgetCopy.ageToday(12) == "12 today!")
    }

    @Test("A snapshot written before birthdays carried their age still reads")
    func oldBirthday() throws {
        let json = #"{"inDays": 2, "text": "Theo turns 5 in 2 days"}"#
        let birthday = try JSONDecoder().decode(WidgetBirthday.self, from: Data(json.utf8))
        #expect(birthday.turning == nil)
        #expect(birthday.text == "Theo turns 5 in 2 days")
    }
}

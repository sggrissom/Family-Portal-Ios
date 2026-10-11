import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Memory widget")
struct WidgetMemoryTests {

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func at(_ day: Int, hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private static func item(_ id: String, _ kind: WidgetItem.Kind, people: [Int] = [7], years: Int? = nil) -> WidgetItem {
        WidgetItem(id: id, kind: kind, date: "2024-05-01", yearsAgo: years, title: kind == .photo ? "" : id,
                   personIds: people, imageFile: kind == .photo ? "\(id).jpg" : nil, link: "/dashboard")
    }

    private static let pool = [
        item("p1", .photo), item("m1", .milestone, people: [8]), item("q1", .quote),
        item("p2", .photo, people: [7, 8]), item("a1", .artwork), item("q2", .quote, people: [8]),
    ]

    private static func snapshot(onThisDay: [String: [WidgetItem]] = [:]) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: Date(), ownerUserId: 1, siteURL: "https://x.test",
                       people: [WidgetPerson(id: 7, name: "Clara"), WidgetPerson(id: 8, name: "Theo")],
                       onThisDay: onThisDay, horizon: "2026-10-24", pool: pool)
    }

    @Test("Content filters by kind; artwork counts as a milestone", arguments: [
        (MemoryFilter.Content.everything, ["p1", "m1", "q1", "p2", "a1", "q2"]),
        (.photos, ["p1", "p2"]),
        (.milestones, ["m1", "a1"]),
        (.quotes, ["q1", "q2"]),
    ])
    func contentFilter(content: MemoryFilter.Content, expected: [String]) {
        #expect(Self.pool.filter(MemoryFilter(content: content).admits).map(\.id) == expected)
    }

    @Test("A person filter keeps what they are in")
    func personFilter() {
        #expect(Self.pool.filter(MemoryFilter(content: .everything, personId: 8).admits).map(\.id) == ["m1", "p2", "q2"])
        #expect(Self.pool.filter(MemoryFilter(content: .quotes, personId: 8).admits).map(\.id) == ["q2"])
    }

    @Test("One memory per rotation slot, the same one within a slot")
    func rotation() {
        let filter = MemoryFilter()
        func id(_ date: Date, hours: Int) -> String? {
            WidgetTimeline.memory(Self.snapshot(), at: date, filter: filter, rotationHours: hours, calendar: Self.utc).featured?.id
        }
        #expect(id(Self.at(11, hour: 6), hours: 6) == id(Self.at(11, hour: 11), hours: 6))
        #expect(id(Self.at(11, hour: 6), hours: 6) != id(Self.at(11, hour: 12), hours: 6))
        #expect(id(Self.at(11, hour: 1), hours: 24) == id(Self.at(11, hour: 23), hours: 24))
        #expect(id(Self.at(11, hour: 23), hours: 24) != id(Self.at(12, hour: 0), hours: 24))
    }

    @Test("Shuffle steps along the filtered pool, wrapping")
    func shuffle() {
        let filter = MemoryFilter(content: .quotes)
        let date = Self.at(11, hour: 9)
        let ids = (0..<3).map {
            WidgetTimeline.memory(Self.snapshot(), at: date, filter: filter, rotationHours: 6, shuffle: $0, calendar: Self.utc).featured!.id
        }
        #expect(Set(ids.prefix(2)) == ["q1", "q2"])
        #expect(ids[0] == ids[2])
    }

    @Test("A filter nothing matches is empty, not signed out")
    func nothingMatches() {
        let moment = WidgetTimeline.memory(Self.snapshot(), at: Date(), filter: MemoryFilter(content: .quotes, personId: 99), rotationHours: 6)
        #expect(moment.source == .nothing)
        #expect(WidgetTimeline.memory(nil, at: Date(), filter: MemoryFilter(), rotationHours: 6).source == .signedOut)
    }

    @Test("Entries land on each rotation boundary for a day")
    func entryDates() {
        let now = Self.at(11, hour: 13)
        #expect(WidgetTimeline.entryDates(from: now, hours: 24, slotHours: 6, calendar: Self.utc) == [
            now, Self.at(11, hour: 18), Self.at(12, hour: 0), Self.at(12, hour: 6), Self.at(12, hour: 12),
        ])
        #expect(WidgetTimeline.entryDates(from: now, hours: 24, slotHours: 24, calendar: Self.utc) == [now, Self.at(12, hour: 0)])
    }

    @Test("On this day, limited to a person, falls back to their memories")
    func onThisDayPersonFilter() {
        let day = [Self.item("t7", .milestone, people: [7], years: 1), Self.item("t8", .photo, people: [8], years: 2)]
        let snapshot = Self.snapshot(onThisDay: ["2026-10-11": day])

        let theo = WidgetTimeline.onThisDay(snapshot, at: Self.at(11, hour: 9), personId: 8, calendar: Self.utc)
        #expect(theo.source == .onThisDay)
        #expect(theo.items.map(\.id) == ["t8"])

        let nobody = WidgetTimeline.onThisDay(snapshot, at: Self.at(11, hour: 9), personId: 99, calendar: Self.utc)
        #expect(nobody.source == .nothing)

        let tomorrow = WidgetTimeline.onThisDay(snapshot, at: Self.at(12, hour: 9), personId: 8, calendar: Self.utc)
        #expect(tomorrow.source == .memory)
        #expect(tomorrow.featured.map { $0.personIds.contains(8) } == true)
    }

    @Test("The shuffle offset advances in the shared defaults")
    func shuffleOffset() {
        let name = "WidgetMemoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        #expect(WidgetShuffle.offset(in: defaults) == 0)
        WidgetShuffle.advance(in: defaults)
        WidgetShuffle.advance(in: defaults)
        #expect(WidgetShuffle.offset(in: defaults) == 2)
    }
}

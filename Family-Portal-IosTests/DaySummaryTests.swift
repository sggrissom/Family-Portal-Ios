import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/daySummary.test.ts, over store records.
@MainActor
@Suite("Day summaries")
struct DaySummaryTests {

    /// Records are inserted so their relationships behave as they do in the app.
    static let context = try! TestStore.makeContext()

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    static func person(_ name: String, born: String, isPregnancy: Bool = false) -> Person {
        let person = Person(name: name, gender: .other, birthday: date(born), isPregnancy: isPregnancy)
        context.insert(person)
        return person
    }

    static func growth(_ person: Person, _ type: MeasurementType, _ value: Double, _ iso: String) -> GrowthData {
        let record = GrowthData(measurementType: type, value: value, unit: type == .height ? .inches : .pounds, date: date(iso))
        context.insert(record)
        record.person = person
        return record
    }

    static func photo(_ iso: String, _ people: [Person], remoteId: Int? = nil) -> Photo {
        let photo = Photo(title: "", descriptionText: "", photoDate: date(iso))
        context.insert(photo)
        photo.taggedPeople = people
        photo.remoteId = remoteId.map(String.init)
        return photo
    }

    static func milestone(_ person: Person, _ iso: String, photoRemoteIds: [Int] = []) -> Milestone {
        let milestone = Milestone(descriptionText: "First steps", category: .first, date: date(iso))
        context.insert(milestone)
        milestone.person = person
        milestone.photoRemoteIds = photoRemoteIds
        return milestone
    }

    let clara = DaySummaryTests.person("Clara", born: "2023-05-02T00:00:00Z")
    let jake = DaySummaryTests.person("Jake", born: "2019-09-26T00:00:00Z")

    @Test("A height and a weight on one day are one checkup")
    func mergesCheckup() {
        let height = Self.growth(clara, .height, 38.5, "2026-09-20T00:00:00Z")
        let weight = Self.growth(clara, .weight, 32, "2026-09-20T00:00:00Z")

        let days = DaySummaries.summarize(DayRecords(growth: [height, weight]), people: [clara], timeZone: .gmt)

        #expect(days.count == 1)
        #expect(days[0].checkups.count == 1)
        #expect(days[0].checkups[0].height === height)
        #expect(days[0].checkups[0].weight === weight)
        #expect(days[0].checkups[0].extra == 0)
    }

    @Test("Extra readings on the same day are counted, not repeated")
    func countsExtraReadings() {
        let records = [
            Self.growth(clara, .height, 38.5, "2026-09-20T00:00:00Z"),
            Self.growth(clara, .height, 38.6, "2026-09-20T00:00:00Z"),
        ]
        let days = DaySummaries.summarize(DayRecords(growth: records), people: [clara], timeZone: .gmt)
        #expect(days[0].checkups[0].extra == 1)
    }

    @Test("A day of photos is one mosaic of the newest four")
    func mosaic() {
        let photos = (1...6).map { index in
            Self.photo("2026-09-21T0\(index):00:00Z", index % 2 == 1 ? [clara] : [jake])
        }
        let day = DaySummaries.summarize(DayRecords(photos: photos), people: [clara, jake], timeZone: .gmt)[0]

        #expect(day.photos?.count == 6)
        #expect(day.photos?.mosaicIds == [photos[5].id, photos[4].id, photos[3].id, photos[2].id])
        #expect(day.photos?.personIds == [jake.id, clara.id])
    }

    @Test("Days are newest first and milestones whole")
    func ordering() {
        let milestone = Self.milestone(clara, "2026-09-22T00:00:00Z")
        let days = DaySummaries.summarize(
            DayRecords(photos: [Self.photo("2026-09-18T12:00:00Z", [])], milestones: [milestone]),
            people: [clara],
            timeZone: .gmt
        )
        #expect(days.map(\.day) == ["2026-09-22", "2026-09-18"])
        #expect(days[0].milestones.map(\.id) == [milestone.id])
    }

    @Test("A photo attached to a milestone is not repeated in the mosaic")
    func attachedPhotosLeaveTheMosaic() {
        let attached = Self.photo("2026-09-22T09:00:00Z", [clara], remoteId: 50)
        let loose = Self.photo("2026-09-22T10:00:00Z", [clara], remoteId: 51)
        let milestone = Self.milestone(clara, "2026-09-22T00:00:00Z", photoRemoteIds: [50])

        let day = DaySummaries.summarize(DayRecords(photos: [attached, loose], milestones: [milestone]), people: [clara], timeZone: .gmt)[0]

        #expect(day.photos?.allIds == [loose.id])
    }

    @Test("Birthdays in the range appear, even on quiet days")
    func birthdays() {
        let days = DaySummaries.summarize(DayRecords(), people: [clara, jake], range: ("2026-09-14", "2026-09-27"), timeZone: .gmt)
        #expect(days.map(\.day) == ["2026-09-26"])
        #expect(days[0].birthdays == [DayBirthday(personId: jake.id, age: 7)])
    }

    @Test("Pregnancies and the day of birth are not birthdays")
    func skipsPregnancyAndBirth() {
        let due = Self.person("Baby", born: "2026-09-20T00:00:00Z", isPregnancy: true)
        let newborn = Self.person("Newborn", born: "2026-09-21T00:00:00Z")
        #expect(DaySummaries.birthdaysBetween([due, newborn], from: "2026-09-14", to: "2026-09-27", timeZone: .gmt).isEmpty)
    }

    @Test("Days group under their month, in order")
    func months() {
        let groups = DaySummaries.groupByMonth([
            DaySummary(day: "2026-09-20"), DaySummary(day: "2026-09-02"), DaySummary(day: "2026-08-30"),
        ])
        #expect(groups.map(\.label) == ["September 2026", "August 2026"])
        #expect(groups.map(\.days.count) == [2, 1])
    }

    @Test("Recent days are named, older ones dated")
    func labels() {
        #expect(DaySummaries.dayLabel("2026-09-27", today: "2026-09-27") == "Today")
        #expect(DaySummaries.dayLabel("2026-09-26", today: "2026-09-27") == "Yesterday")
        #expect(DaySummaries.dayLabel("2026-09-19", today: "2026-09-27") == "Saturday, Sep 19")
        #expect(DaySummaries.dayLabel("2025-12-31", today: "2026-01-02") == "Wednesday, Dec 31, 2025")
    }

    @Test("Appearances at one event are one card, dated by when they happened")
    func events() throws {
        func appearance(_ id: Int, event: Int, occurredAt: String, start: String) throws -> TimelineAppearanceDTO {
            try APIClient.decode(TimelineAppearanceDTO.self, from: Fixture.data([
                "detail": Fixture.appearanceDetail(
                    Fixture.appearance(id: id, eventId: event, occurredAt: occurredAt),
                    entry: Fixture.activityEntry(id: id),
                    event: Fixture.eventSummary(id: event, startDate: start)
                ),
                "personIds": [1],
            ]))
        }
        let appearances = [
            try appearance(1, event: 10, occurredAt: "2026-09-20T15:00:00Z", start: "2026-09-19T00:00:00Z"),
            try appearance(2, event: 10, occurredAt: "2026-09-20T17:00:00Z", start: "2026-09-19T00:00:00Z"),
            try appearance(3, event: 11, occurredAt: "0001-01-01T00:00:00Z", start: "2026-09-12T00:00:00Z"),
        ]

        let days = DaySummaries.summarize(DayRecords(appearances: appearances), people: [], timeZone: .gmt)

        #expect(days.map(\.day) == ["2026-09-20", "2026-09-12"])
        #expect(days.map { $0.events.map(\.event.id) } == [[10], [11]])
        #expect(days[0].events[0].appearances.count == 2)
    }
}

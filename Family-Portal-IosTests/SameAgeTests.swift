import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Same age")
struct SameAgeTests {

    private let a = UUID()
    private let b = UUID()

    // MARK: - Anchor for a photo

    @Test("A photo opened from a person's page anchors on them")
    func openedFromAnchors() {
        #expect(SameAgeAnchor.initial(tagged: [a, b], openedFrom: b) == b)
    }

    @Test("A group photo opened from Photos picks nobody invisibly")
    func groupPhotoPicksNobody() {
        #expect(SameAgeAnchor.initial(tagged: [a, b], openedFrom: nil) == nil)
    }

    @Test("A photo of one person anchors on them")
    func onePersonAnchors() {
        #expect(SameAgeAnchor.initial(tagged: [a], openedFrom: nil) == a)
    }

    @Test("A page the photo's people don't include is not an anchor")
    func openedFromSomeoneElse() {
        #expect(SameAgeAnchor.initial(tagged: [a, b], openedFrom: UUID()) == nil)
    }

    // MARK: - Rows

    private func row(birthday: String = "2020-08-04T00:00:00Z", date: String) throws -> SameAgeRowDTO {
        try APIClient.decode(SameAgeRowDTO.self, from: Fixture.data([
            "person": Fixture.person(id: 4, birthday: birthday),
            "date": date,
            "height": Fixture.growthData(id: 1, personId: 4, measurementType: 0, value: 38.5, unit: "in", measurementDate: "2023-12-10T00:00:00Z"),
            "weight": NSNull(),
            "milestones": [],
            "photoIds": [],
        ]))
    }

    @Test("A row says the month the person reached the age")
    func whenIsAMonth() throws {
        let row = try row(date: "2023-12-04T00:00:00Z")
        let today = ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z")!
        #expect(SameAgeText.when(row, ageMonths: 40, today: today) == "Dec 2023")
    }

    @Test("A row for someone that age today says now")
    func whenIsNow() throws {
        let row = try row(date: "2023-12-04T00:00:00Z")
        let today = ISO8601DateFormatter().date(from: "2023-12-20T12:00:00Z")!
        #expect(SameAgeText.when(row, ageMonths: 40, today: today) == Copy.sameAge.now)
    }

    @Test("Measurements read at the age they were taken")
    func measurements() throws {
        #expect(SameAgeText.measurements(try row(date: "2023-12-04T00:00:00Z")) == "3 ft 2.5 in")
    }

    @Test("The strip's heading names birth as birth")
    func heading() {
        #expect(Copy.sameAge.atThisAge(AgeSteps.ageTitle(0)) == "At birth")
        #expect(Copy.sameAge.atThisAge(AgeSteps.ageTitle(40)) == "At 3 years 4 months")
    }

    // MARK: - Montage

    private func portrait(_ photoId: Int) -> [String: Any] {
        ["photoId": photoId, "box": ["left": 0.3, "top": 0.2, "right": 0.7, "bottom": 0.6], "date": "2014-09-10T15:30:00Z", "ageMonths": 6, "year": 2014]
    }

    private func montageRow(id: Int, portraits: [[String: Any]]?) throws -> SameAgeRowDTO {
        var payload: [String: Any] = [
            "person": Fixture.person(id: id),
            "date": "2014-09-02T00:00:00Z",
            "height": NSNull(),
            "weight": NSNull(),
            "milestones": [],
            "photoIds": [],
        ]
        if let portraits { payload["portraits"] = portraits }
        return try APIClient.decode(SameAgeRowDTO.self, from: Fixture.data(payload))
    }

    @Test("Portraits decode with their face box, and a server without them sends none")
    func portraitsDecode() throws {
        let row = try montageRow(id: 4, portraits: [portrait(9)])
        #expect(row.portraits.map(\.photoId) == [9])
        #expect(row.portraits[0].box.right == 0.7)
        #expect(try montageRow(id: 5, portraits: nil).portraits.isEmpty)
    }

    @Test("The montage needs two people with a photo, and lists the rest as a gap")
    func montageRows() throws {
        let mia = try montageRow(id: 4, portraits: [portrait(9), portrait(10)])
        let ben = try montageRow(id: 5, portraits: [portrait(11)])
        let ava = try montageRow(id: 6, portraits: [])

        #expect(!SameAgeMontageRows.shows([mia, ava]))
        #expect(SameAgeMontageRows.shows([mia, ava, ben]))
        #expect(SameAgeMontageRows.pictured([mia, ava, ben]).map(\.id) == [4, 5])
        #expect(SameAgeMontageRows.missing([mia, ava, ben]).map(\.id) == [6])
    }

    @Test("Another photo cycles back to the best")
    func nextPick() {
        #expect(SameAgeMontageRows.nextPick(0, count: 2) == 1)
        #expect(SameAgeMontageRows.nextPick(1, count: 2) == 0)
        #expect(SameAgeMontageRows.nextPick(0, count: 0) == 0)
    }

    @Test("The gap line names who has no photo")
    func noPhotoCopy() {
        #expect(Copy.sameAge.noPhoto("Mia, Ben") == "No photo near this age: Mia, Ben")
    }
}

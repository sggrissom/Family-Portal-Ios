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

    @Test("Portraits read oldest first")
    func portraitOrder() throws {
        let rows = try [
            APIClient.decode(SameAgeRowDTO.self, from: Fixture.data(["person": Fixture.person(id: 5, birthday: "2021-01-01T00:00:00Z"), "date": "2021-07-01T00:00:00Z", "milestones": [], "photoIds": []])),
            APIClient.decode(SameAgeRowDTO.self, from: Fixture.data(["person": Fixture.person(id: 4, birthday: "2018-03-01T00:00:00Z"), "date": "2018-09-01T00:00:00Z", "milestones": [], "photoIds": []])),
        ]
        #expect(SameAgeText.portraitOrder(rows).map(\.id) == [4, 5])
    }

    @Test("The empty and missing-photo lines name newborns as newborns")
    func portraitCopy() {
        #expect(Copy.sameAge.noPortraits("Newborn") == "No newborn photos yet.")
        #expect(Copy.sameAge.noPortraits("3 years") == "No photos from around 3 years yet.")
        #expect(Copy.sameAge.missingPhotos("Newborn", 1) == "No newborn photo for 1 person")
        #expect(Copy.sameAge.missingPhotos("6 months", 2) == "No 6 months photo for 2 people")
        #expect(Copy.sameAge.peopleWithRecords(1) == "1 person has records")
        #expect(Copy.sameAge.missingRecords(3) == "3 other people have no records near this age.")
    }
}

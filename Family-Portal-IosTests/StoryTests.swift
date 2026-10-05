import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/story.test.ts.
@MainActor
@Suite("Story")
struct StoryTests {

    private let person = DaySummaryTests.person("Clara", born: "2023-05-02T00:00:00Z")

    private func days() -> [DaySummary] {
        let growth = [
            DaySummaryTests.growth(person, .height, 35, "2026-05-10T00:00:00Z"),
            DaySummaryTests.growth(person, .weight, 28, "2026-05-10T00:00:00Z"),
            DaySummaryTests.growth(person, .height, 38, "2026-09-20T00:00:00Z"),
            DaySummaryTests.growth(person, .weight, 32, "2026-09-20T00:00:00Z"),
            DaySummaryTests.growth(person, .height, 33, "2025-12-01T00:00:00Z"),
        ]
        let photo = DaySummaryTests.photo("2023-04-20T00:00:00Z", [])
        return DaySummaries.summarize(DayRecords(photos: [photo], growth: growth), people: [])
    }

    @Test("Days group by age, newest first")
    func groupsByAge() {
        let chapters = Story.chapters(days(), birthday: person.birthday!)
        #expect(chapters.map(\.age) == [3, 2, nil])
        #expect(chapters.map { Story.chapterTitle($0.age) } == ["Age 3", "Age 2", "Before birth"])
    }

    @Test("A chapter says how much they grew")
    func grew() {
        let chapters = Story.chapters(days(), birthday: person.birthday!)
        #expect(chapters[0].grew == "Grew 3 in and 4 lb")
        #expect(chapters[1].grew == "")
    }

    @Test("The first year is named")
    func firstYear() {
        #expect(Story.chapterTitle(0) == "First year")
    }
}

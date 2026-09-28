import Foundation

/// A year of someone's life on their Story tab.
struct StoryChapter: Identifiable {
    /// Whole years old; nil before birth.
    let age: Int?
    var days: [DaySummary]
    var grew: String

    var id: String { age.map(String.init) ?? "before" }
}

/// Groups a person's days into age chapters — a port of frontend/lib/story.ts.
enum Story {

    /// Days newest first in, chapters newest first out.
    static func chapters(_ days: [DaySummary], birthday: Date) -> [StoryChapter] {
        var chapters: [StoryChapter] = []
        for day in days {
            guard let date = DaySummaries.date(of: day.day) else { continue }
            let months = AgeSteps.monthsOld(birthday: birthday, at: date)
            let age: Int? = months < 0 ? nil : months / 12
            if let last = chapters.last, last.age == age {
                chapters[chapters.count - 1].days.append(day)
            } else {
                chapters.append(StoryChapter(age: age, days: [day], grew: ""))
            }
        }
        for index in chapters.indices {
            chapters[index].grew = grewLine(chapters[index].days)
        }
        return chapters
    }

    static func chapterTitle(_ age: Int?) -> String {
        guard let age else { return "Before birth" }
        return age == 0 ? "First year" : "Age \(age)"
    }

    /// "Grew 3 in and 4 lb" across a chapter's checkups; empty when neither moved enough to say.
    static func grewLine(_ days: [DaySummary]) -> String {
        let heights = days.flatMap { $0.checkups.compactMap(\.height) }
        let weights = days.flatMap { $0.checkups.compactMap(\.weight) }
        var parts: [String] = []
        if let h = change(heights), h >= 0.25 {
            parts.append("\(rounded(h, places: 1)) in")
        }
        if let w = change(weights), w >= 0.5 {
            parts.append("\(rounded(w, places: w < 10 ? 1 : 0)) lb")
        }
        return parts.isEmpty ? "" : "Grew \(parts.joined(separator: " and "))"
    }

    private static func change(_ records: [GrowthData]) -> Double? {
        guard records.count >= 2 else { return nil }
        let sorted = records.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        return AgeChart.toDisplay(last.value, unit: last.unit) - AgeChart.toDisplay(first.value, unit: first.unit)
    }

    /// `String(Math.round(v * f) / f)`: no trailing zeros.
    private static func rounded(_ value: Double, places: Int) -> String {
        let factor = pow(10, Double(places))
        let result = (value * factor).rounded() / factor
        return result == result.rounded() ? String(Int(result)) : String(result)
    }
}

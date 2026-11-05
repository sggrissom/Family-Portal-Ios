import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/recordWhen.test.ts, so both clients build the same assertions.
@MainActor
@Suite("Record when entry")
struct RecordWhenEntryTests {

    static let now = ISO8601DateFormatter().date(from: "2026-11-02T18:00:00Z")!
    static let born = ISO8601DateFormatter().date(from: "2020-06-15T00:00:00Z")!

    static func entry(_ change: (inout RecordWhenEntry) -> Void) -> RecordWhenEntry {
        var entry = RecordWhenEntry()
        entry.anchorPersonId = 7
        change(&entry)
        return entry
    }

    @Test("A whole year of age, or month precision once months are given")
    func agePrecision() {
        let year = Self.entry { $0.mode = .age; $0.ageYears = 4; $0.meaning = "period" }.recordTime(isMoment: true)
        #expect(year.precision == "year")
        #expect(year.anchorPersonId == 7)
        #expect(year.label == "At age 4")
        let zero = Self.entry { $0.mode = .age; $0.ageYears = 4; $0.ageMonths = 0 }.recordTime(isMoment: true)
        #expect(zero.precision == "month")
    }

    @Test("Builds the plan's examples")
    func examples() {
        let cases: [(RecordWhenEntry, Bool, String)] = [
            (Self.entry { $0.mode = .month; $0.month = 10; $0.monthYear = 2022 }, true, "October 2022"),
            (Self.entry { $0.mode = .year; $0.year = 1970 }, false, "1970"),
            (Self.entry { $0.mode = .range; $0.rangeFrom = "1968"; $0.rangeTo = "1972"; $0.estimated = true; $0.around = "1970" }, false, "Around 1970 (1968–1972)"),
            (Self.entry { $0.mode = .age; $0.ageYears = 4; $0.meaning = "occurrence" }, true, "Sometime at age 4"),
            (Self.entry { $0.mode = .age; $0.ageYears = 6; $0.ageToYears = 9; $0.estimated = true; $0.around = "8" }, false, "Around age 8 (ages 6–9)"),
            (Self.entry { $0.mode = .unknown; $0.estimated = true }, true, "Date unknown"),
        ]
        for (entry, isMoment, label) in cases {
            #expect(entry.recordTime(now: Self.now, isMoment: isMoment).label == label)
        }
    }

    @Test("A photo never describes a period")
    func photosHappen() {
        let rt = Self.entry { $0.mode = .age; $0.ageYears = 4; $0.meaning = "period" }.recordTime(isMoment: false)
        #expect(rt.meaning == "occurrence")
    }

    @Test("Round-trips through the editor")
    func roundTrip() {
        let entries = [
            Self.entry { $0.mode = .month; $0.month = 10; $0.monthYear = 2022 },
            Self.entry { $0.mode = .range; $0.rangeFrom = "1968"; $0.rangeTo = "1972-06"; $0.estimated = true; $0.around = "1970" },
            Self.entry { $0.mode = .age; $0.ageYears = 4; $0.ageMonths = 3; $0.meaning = "period" },
            Self.entry { $0.mode = .age; $0.ageYears = 6; $0.ageToYears = 9; $0.meaning = "occurrence" },
            Self.entry { $0.mode = .unknown },
        ]
        for entry in entries {
            let rt = entry.recordTime(now: Self.now, isMoment: true)
            let again = RecordWhenEntry(recordTime: rt, date: Date()).recordTime(now: Self.now, isMoment: true)
            #expect(again == rt)
        }
    }

    @Test("Resolves against the birthday for sorting on the device")
    func resolves() {
        let rt = Self.entry { $0.mode = .age; $0.ageYears = 4; $0.meaning = "period" }.recordTime(isMoment: true, birthday: Self.born)
        #expect(rt.start == "2024-06-15")
        #expect(rt.end == "2025-06-15")
        #expect(RecordWhenEntry.sortDate(rt).recordDayKey == "2024-06-15")
        var unknown = RecordTime()
        unknown.basis = "unknown"
        #expect(RecordWhenEntry.sortDate(unknown).recordDayKey == "0001-01-01")
    }

    @Test("Checks what the web checks")
    func problems() {
        func problem(_ change: (inout RecordWhenEntry) -> Void) -> String? {
            var entry = Self.entry { $0.meaning = "occurrence" }
            change(&entry)
            return entry.problem(isMoment: true, birthday: Self.born, now: Self.now)
        }
        #expect(problem { $0.mode = .range; $0.rangeFrom = "1972"; $0.rangeTo = "1968" } == "The range ends before it starts")
        #expect(problem { $0.mode = .range; $0.rangeFrom = "1968" } == "Enter both ends, like 1968 and 1972")
        #expect(problem { $0.mode = .age; $0.ageYears = 9; $0.ageToYears = 6 } == "The age range ends before it starts")
        #expect(problem { $0.mode = .age; $0.ageYears = 7 } == "That age hasn't happened yet")
        #expect(problem { $0.mode = .age; $0.ageYears = 6 } == nil)
        #expect(problem { $0.mode = .age; $0.ageYears = 4; $0.anchorPersonId = 0 } == "Choose whose age this is")
        #expect(problem { $0.mode = .age; $0.ageYears = 4; $0.meaning = "" } == "Choose whether it happened then or describes that age")
    }

    @Test("Shows the age window from the birthday")
    func preview() {
        let preview = Self.entry { $0.mode = .age; $0.ageYears = 4; $0.meaning = "period" }
            .preview(isMoment: true, birthday: Self.born, now: Self.now)
        #expect(preview?.label == "At age 4")
        #expect(preview?.bounds.hasPrefix("Based on birthday: ") == true)
        #expect(Self.entry { $0.mode = .today }.preview(isMoment: true, birthday: nil, now: Self.now) == nil)
    }

    // MARK: - Mode transitions (frontend/lib/recordWhen.test.ts, "date mode transitions")

    @Test("Today, Yesterday and Not sure ignore hidden period and estimate choices", arguments: [RecordWhenMode.today, .yesterday, .unknown])
    func hiddenChoicesIgnored(mode: RecordWhenMode) {
        let entry = Self.entry { $0.mode = mode; $0.meaning = "period"; $0.estimated = true; $0.around = "invalid" }
        let rt = entry.recordTime(now: Self.now, isMoment: true)
        #expect(rt.meaning == "occurrence")
        #expect(rt.estimated == false)
        #expect(rt.around == "")
        #expect(entry.problem(isMoment: true, birthday: nil, now: Self.now) == nil)
    }

    @Test("Switching an estimated age period to a shortcut clears what the shortcut hides", arguments: [RecordWhenMode.today, .yesterday, .unknown])
    func switchClearsChoices(mode: RecordWhenMode) {
        var entry = Self.entry { $0.mode = .age; $0.ageYears = 6; $0.ageToYears = 9; $0.meaning = "period"; $0.estimated = true; $0.around = "8" }
        entry.setMode(mode)
        #expect(entry.meaning == "")
        #expect(entry.estimated == false)
        #expect(entry.around == "")
        let rt = entry.recordTime(now: Self.now, isMoment: true)
        #expect(rt.basis == (mode == .unknown ? "unknown" : "calendar"))
        if mode != .unknown {
            #expect(rt.isExactDay)
            #expect(entry.isApproximate == false)
        }
    }

    @Test("A central age never carries into a calendar range, or back")
    func bestGuessDoesNotCarry() {
        var entry = Self.entry { $0.mode = .age; $0.ageYears = 6; $0.ageToYears = 9; $0.meaning = "period"; $0.estimated = true; $0.around = "8" }
        entry.setMode(.range)
        entry.rangeFrom = "1968"
        entry.rangeTo = "1972"
        #expect(entry.around == "")
        #expect(entry.problem(isMoment: true, birthday: nil, now: Self.now) == nil)
        #expect(entry.recordTime(now: Self.now, isMoment: true).label == "Around 1968–1972")
        entry.around = "1970"
        #expect(entry.recordTime(now: Self.now, isMoment: true).around == "1970")
        entry.setMode(.age)
        #expect(entry.around == "")
    }

    @Test("An age range narrowed to one age drops its best guess")
    func singleAgeDropsGuess() {
        var entry = Self.entry { $0.mode = .age; $0.ageYears = 4; $0.ageToYears = 6; $0.estimated = true; $0.around = "5" }
        entry.ageToYears = nil
        #expect(entry.controls.bestGuess == false)
        let rt = entry.recordTime(now: Self.now, isMoment: true)
        #expect(rt.around == "")
        #expect(rt.label == "Around age 4")
    }

    @Test("A period on a calendar day is approximate, so it gets no photo suggestions")
    func periodOnADay() {
        let entry = Self.entry { $0.mode = .date; $0.date = Self.born; $0.meaning = "period" }
        #expect(entry.isApproximate)
        #expect(entry.recordTime(now: Self.now, isMoment: true).isExactDay == false)
    }
}

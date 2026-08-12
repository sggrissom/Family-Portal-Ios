import SwiftUI

/// The three ways the backend lets a date be given for growth data and
/// milestones — `inputType` is `"today" | "date" | "age"` in backend/growth.go
/// and backend/milestone.go. Entering "at 14 months" beats scrolling a date
/// picker back two years on a phone.
enum DateEntryMode: String, CaseIterable, Identifiable {
    case today
    case date
    case age

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .date: return "Date"
        case .age: return "Age"
        }
    }
}

/// Form rows that resolve a date from whichever mode the user picks.
///
/// The resolved date is what gets stored and sent, rather than passing
/// `inputType: "age"` through to the server: the local record needs a concrete
/// date the moment it's created, and Go's `AddDate` and Foundation's `Calendar`
/// disagree about month overflow (Jan 31 plus one month is Mar 3 in Go, Feb 28
/// here). Resolving it in one place keeps the device and the server from
/// storing different days for the same entry.
struct DateEntryPicker: View {
    /// The person's birthday. Age entry is hidden when it's unknown, since
    /// there is nothing to count from.
    let birthday: Date?
    @Binding var date: Date

    @State private var mode: DateEntryMode = .today
    @State private var ageYears = 0
    @State private var ageMonths = 0

    private var availableModes: [DateEntryMode] {
        birthday == nil ? [.today, .date] : DateEntryMode.allCases
    }

    static func date(from birthday: Date, years: Int, months: Int) -> Date {
        Calendar.current.date(
            byAdding: DateComponents(year: years, month: months),
            to: birthday
        ) ?? birthday
    }

    var body: some View {
        Group {
            Picker("Date Entry", selection: $mode) {
                ForEach(availableModes) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .today:
                LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .omitted))
            case .date:
                DatePicker("Date", selection: $date, displayedComponents: .date)
            case .age:
                Stepper("\(ageYears) \(ageYears == 1 ? "year" : "years")", value: $ageYears, in: 0...30)
                Stepper("\(ageMonths) \(ageMonths == 1 ? "month" : "months")", value: $ageMonths, in: 0...11)
                LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .onChange(of: mode) { _, newMode in resolve(for: newMode) }
        .onChange(of: ageYears) { _, _ in resolve(for: mode) }
        .onChange(of: ageMonths) { _, _ in resolve(for: mode) }
    }

    private func resolve(for mode: DateEntryMode) {
        switch mode {
        case .today:
            date = Date()
        case .date:
            // Leave the date alone: it's whatever the picker last showed, which
            // is the sensible starting point for editing it.
            break
        case .age:
            guard let birthday else { return }
            date = Self.date(from: birthday, years: ageYears, months: ageMonths)
        }
    }
}

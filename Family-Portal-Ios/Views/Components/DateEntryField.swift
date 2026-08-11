import SwiftUI

/// How the user chose to express when something happened. The backend accepts
/// the same three modes on `AddGrowthData`, `AddMilestone`, and their update
/// counterparts (`inputType: "today" | "date" | "age"`).
enum DateEntryMode: String, CaseIterable, Identifiable, Sendable {
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

/// What a date entry resolves to: a concrete date for the local model, plus the
/// wire parameters the backend needs to agree with it.
struct DateEntryResult: Sendable {
    let date: Date
    let inputType: String
    let ageYears: Int?
    let ageMonths: Int?
}

/// Picking "at 14 months" is materially easier on a phone than scrolling a date
/// picker back two years, which is the whole point of supporting age entry.
struct DateEntryField: View {
    @Binding var mode: DateEntryMode
    @Binding var date: Date
    @Binding var ageYears: Int
    @Binding var ageMonths: Int

    /// Age entry needs a birthday to resolve against; without one the mode is
    /// hidden rather than offered and then rejected.
    let birthday: Date?

    private var availableModes: [DateEntryMode] {
        birthday == nil ? [.today, .date] : DateEntryMode.allCases
    }

    var body: some View {
        Picker("When", selection: $mode) {
            ForEach(availableModes) { entryMode in
                Text(entryMode.label).tag(entryMode)
            }
        }
        .pickerStyle(.segmented)

        switch mode {
        case .today:
            LabeledContent("Date", value: Date.now.formatted(date: .abbreviated, time: .omitted))

        case .date:
            DatePicker("Date", selection: $date, displayedComponents: .date)

        case .age:
            Picker("Years", selection: $ageYears) {
                ForEach(0...25, id: \.self) { year in
                    Text(year == 1 ? "1 year" : "\(year) years").tag(year)
                }
            }
            Picker("Months", selection: $ageMonths) {
                ForEach(0...11, id: \.self) { month in
                    Text(month == 1 ? "1 month" : "\(month) months").tag(month)
                }
            }

            if let resolved = Self.dateFromAge(birthday: birthday, years: ageYears, months: ageMonths) {
                LabeledContent("Date", value: resolved.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Mirrors `personBirthday.AddDate(years, months, 0)` in backend/growth.go
    /// and backend/milestone.go — calendar arithmetic, not a fixed number of days.
    static func dateFromAge(birthday: Date?, years: Int, months: Int) -> Date? {
        guard let birthday else { return nil }
        return Calendar.current.date(byAdding: DateComponents(year: years, month: months), to: birthday)
    }

    /// Resolves the current selection for both the local model and the wire.
    static func resolve(
        mode: DateEntryMode,
        date: Date,
        ageYears: Int,
        ageMonths: Int,
        birthday: Date?
    ) -> DateEntryResult {
        switch mode {
        case .today:
            // Sent as an explicit date rather than inputType "today": the
            // backend resolves "today" with time.Now() when the operation is
            // *synced*, so a queue that sat offline for three days would record
            // the wrong day.
            return DateEntryResult(date: Date(), inputType: "date", ageYears: nil, ageMonths: nil)

        case .date:
            return DateEntryResult(date: date, inputType: "date", ageYears: nil, ageMonths: nil)

        case .age:
            guard let resolved = dateFromAge(birthday: birthday, years: ageYears, months: ageMonths) else {
                return DateEntryResult(date: date, inputType: "date", ageYears: nil, ageMonths: nil)
            }
            // Sends the age itself so the server records the same intent the
            // website does; its computed date comes back on the response and
            // overwrites the local one, so the two can't drift.
            return DateEntryResult(
                date: resolved,
                inputType: "age",
                ageYears: ageYears,
                ageMonths: ageMonths
            )
        }
    }
}

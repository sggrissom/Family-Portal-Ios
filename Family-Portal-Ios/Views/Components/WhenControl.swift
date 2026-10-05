import SwiftUI

/// "Today ▾" — a menu labelled with the current choice, offering Today, Yesterday, Pick a date… and By age…. Replaced the old segmented `DateEntryPicker`.
/// Callers key it with `.id(person?.id)`: an age is resolved against the birthday it was handed, so a control carried over to somebody else would hold a date worked out from the wrong one.
struct WhenControl: View {
    @Binding var entry: WhenEntry
    /// The person's birthday. By age… is offered only when there is one to count from.
    let birthday: Date?

    private var modes: [WhenMode] {
        birthday == nil ? [.today, .yesterday, .date] : WhenMode.allCases
    }

    var body: some View {
        LabeledContent(Copy.when.label) {
            Menu {
                ForEach(modes) { mode in
                    Button {
                        choose(mode)
                    } label: {
                        if entry.mode == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(entry.menuLabel)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .accessibilityLabel("\(Copy.when.label): \(entry.menuLabel)")
        }

        switch entry.mode {
        case .today, .yesterday:
            EmptyView()
        case .date:
            DatePicker(
                Copy.when.date,
                selection: Binding(
                    get: { entry.date ?? Date() },
                    set: { entry.date = $0 }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
        case .age:
            Stepper(value: Binding(get: { entry.ageYears ?? 0 }, set: { entry.ageYears = $0 }), in: 0...30) {
                LabeledContent(Copy.when.years, value: "\(entry.ageYears ?? 0)")
            }
            Stepper(value: Binding(get: { entry.ageMonths ?? 0 }, set: { entry.ageMonths = $0 }), in: 0...11) {
                LabeledContent(Copy.when.months, value: "\(entry.ageMonths ?? 0)")
            }
            if let birthday, let resolved = entry.resolvedDate(birthday: birthday) {
                LabeledContent(Copy.when.date, value: resolved.displayDay().formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func choose(_ mode: WhenMode) {
        entry.mode = mode
        switch mode {
        case .date where entry.date == nil:
            entry.date = Calendar.current.startOfDay(for: Date())
        case .age where entry.ageYears == nil:
            entry.ageYears = 0
            entry.ageMonths = 0
        default:
            break
        }
    }
}

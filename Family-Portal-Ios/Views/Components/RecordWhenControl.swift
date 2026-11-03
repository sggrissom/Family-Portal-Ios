import SwiftUI

/// The "When" rows once the server takes approximate dates: Today, Yesterday and a picked day as before, plus a month, a year, a range, an age (or ages) and Not sure — the web's `RecordWhenControl`.
/// A moment entered by age says whether it happened sometime then or describes that time; a photo always happened. Lives inside a `Section`.
struct RecordWhenControl: View {
    @Binding var entry: RecordWhenEntry
    let isMoment: Bool
    /// The anchor's birthday, for the preview and the future check.
    let birthday: Date?
    /// People whose age a photo could be dated by. A moment passes none: it is dated by its own person's age.
    var anchors: [Person] = []

    var body: some View {
        LabeledContent(Copy.when.label) {
            Menu {
                ForEach(RecordWhenMode.allCases) { mode in
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
                    Text(entry.mode.label)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .accessibilityLabel("\(Copy.when.label): \(entry.mode.label)")
        }

        switch entry.mode {
        case .today, .yesterday, .unknown:
            EmptyView()
        case .date:
            DatePicker(
                Copy.when.date,
                selection: Binding(get: { entry.date ?? Date() }, set: { entry.date = $0 }),
                in: ...Date(),
                displayedComponents: .date
            )
        case .month:
            Picker(Copy.recordWhen.month, selection: $entry.month) {
                ForEach(1...12, id: \.self) { month in
                    Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                }
            }
            yearField(Copy.recordWhen.year, value: $entry.monthYear)
        case .year:
            yearField(Copy.recordWhen.year, value: $entry.year)
        case .range:
            TextField(Copy.recordWhen.rangeFrom, text: $entry.rangeFrom, prompt: Text("1968"))
                .keyboardType(.numbersAndPunctuation)
            TextField(Copy.recordWhen.rangeTo, text: $entry.rangeTo, prompt: Text("1972"))
                .keyboardType(.numbersAndPunctuation)
        case .age:
            if !anchors.isEmpty {
                Picker(Copy.recordWhen.whoseAge, selection: $entry.anchorPersonId) {
                    Text(Copy.recordWhen.choosePerson).tag(0)
                    ForEach(anchors.filter { $0.serverId != nil }) { person in
                        Text(person.name).tag(person.serverId ?? 0)
                    }
                }
            }
            Stepper(value: $entry.ageYears, in: 0...100) {
                LabeledContent(entry.ageToYears == nil ? Copy.when.years : Copy.recordWhen.ageFrom, value: "\(entry.ageYears)")
            }
            if entry.ageToYears == nil {
                Toggle(Copy.recordWhen.withMonths, isOn: Binding(
                    get: { entry.ageMonths != nil },
                    set: { entry.ageMonths = $0 ? 0 : nil }
                ))
                if let months = entry.ageMonths {
                    Stepper(value: Binding(get: { months }, set: { entry.ageMonths = $0 }), in: 0...11) {
                        LabeledContent(Copy.when.months, value: "\(months)")
                    }
                }
            }
            if entry.ageMonths == nil {
                Toggle(Copy.recordWhen.ageRange, isOn: Binding(
                    get: { entry.ageToYears != nil },
                    set: { entry.ageToYears = $0 ? entry.ageYears + 1 : nil }
                ))
                if let to = entry.ageToYears {
                    Stepper(value: Binding(get: { to }, set: { entry.ageToYears = $0 }), in: entry.ageYears...100) {
                        LabeledContent(Copy.recordWhen.ageTo, value: "\(to)")
                    }
                }
            }
        }

        if isMoment && !entry.mode.isDay && entry.mode != .unknown {
            Picker(Copy.recordWhen.meaning, selection: $entry.meaning) {
                Text(Copy.recordWhen.happened).tag("occurrence")
                Text(Copy.recordWhen.describes).tag("period")
            }
            .pickerStyle(.inline)
        }

        if entry.mode != .unknown && entry.mode != .today && entry.mode != .yesterday {
            Toggle(Copy.recordWhen.estimate, isOn: $entry.estimated)
            if entry.estimated && (entry.mode == .range || entry.ageToYears != nil) {
                TextField(Copy.recordWhen.bestGuess, text: $entry.around, prompt: Text(entry.mode == .age ? "8" : "1970"))
                    .keyboardType(.numbersAndPunctuation)
            }
        }

        if let preview = entry.preview(isMoment: isMoment, birthday: birthday) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.label).font(.subheadline.weight(.semibold))
                if !preview.bounds.isEmpty {
                    Text(preview.bounds).font(.caption)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func yearField(_ title: String, value: Binding<Int?>) -> some View {
        TextField(title, text: Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0.filter(\.isNumber).prefix(4)) }
        ), prompt: Text("1970"))
        .keyboardType(.numberPad)
    }

    private func choose(_ mode: RecordWhenMode) {
        entry.mode = mode
        if mode == .date, entry.date == nil {
            entry.date = Calendar.current.startOfDay(for: Date())
        }
        if mode == .age, entry.anchorPersonId == 0, anchors.count == 1 {
            entry.anchorPersonId = anchors[0].serverId ?? 0
        }
    }
}

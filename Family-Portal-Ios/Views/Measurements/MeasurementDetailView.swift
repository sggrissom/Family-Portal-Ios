import SwiftUI
import SwiftData

/// The whole measurement, shown when a row is tapped. Tapping used to drop straight into the editor; a measurement
/// is recorded once and read back many times, so the editor now sits behind the Edit button here.
/// Shared by the measurement list and the timeline.
/// Past the value itself it answers what the web's measurement page does: where it sits against the WHO/CDC
/// reference population, and how the rest of the family measured at the same age — all from local data, so it reads the same offline.
struct MeasurementDetailSheetView: View {
    let measurement: GrowthData

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    /// The whole roster and graph, for the family comparison. A sheet can't narrow a `@Query` to one family any better than the add sheets can, and the store only ever holds the signed-in family.
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]

    private var person: Person? { measurement.person }
    private var ageMonths: Double? { MeasurementConversion.ageMonths(of: measurement) }
    private var typeNoun: String { measurement.measurementType.rawValue }

    /// The same number in the other unit this type is kept in, so a record entered in pounds still answers "how many kilos".
    private var alternateValue: (label: String, value: String)? {
        guard let other = measurement.measurementType.validUnits.first(where: { $0 != measurement.unit }) else {
            return nil
        }
        let converted = MeasurementConversion.convert(measurement.value, from: measurement.unit, to: other)
        return ("In \(other.rawValue)", MeasurementConversion.format(
            converted,
            unit: other,
            ageMonths: ageMonths
        ))
    }

    /// This person's other records of the same type, for the "since last" row and last time's percentile.
    private var siblingSamples: [GrowthComparison.Sample] {
        (person?.growthData ?? [])
            .filter { $0.measurementType == measurement.measurementType && $0.id != measurement.id }
            .map { GrowthComparison.Sample($0) }
    }

    private var change: GrowthComparison.Change? {
        GrowthComparison.change(from: siblingSamples, to: GrowthComparison.Sample(measurement))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailSheetHeader(
                        icon: measurement.measurementType.icon,
                        tint: measurement.measurementType.color,
                        badge: measurement.measurementType.label,
                        title: MeasurementConversion.format(measurement),
                        titleFont: .largeTitle
                    )

                    facts
                    percentileSection
                    familySection
                }
                .padding()
            }
            .navigationTitle("Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {
                        isEditing = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                EditMeasurementView(measurement: measurement)
            }
        }
    }

    // MARK: - Facts

    private var facts: some View {
        DetailFieldGroup {
            DetailFieldRow(
                label: "Date",
                value: measurement.date.formatted(date: .long, time: .omitted)
            )

            if let person {
                Divider()
                DetailFieldRow(label: "Person", value: person.name)

                if let age = person.age(on: measurement.date) {
                    Divider()
                    DetailFieldRow(label: "Age", value: age)
                }
            }

            if let alternateValue {
                Divider()
                DetailFieldRow(label: alternateValue.label, value: alternateValue.value)
            }

            if let change {
                Divider()
                DetailFieldRow(label: "Since last", value: changeText(change))
            }
        }
    }

    /// "+1.2 in over 3 wk", in this record's unit whatever the last one was entered in.
    private func changeText(_ change: GrowthComparison.Change) -> String {
        let elapsed = GrowthComparison.formatElapsed(days: change.elapsedDays)
        let magnitude = GrowthComparison.formatMagnitude(
            abs(change.difference),
            unit: measurement.unit,
            ageMonths: ageMonths
        )
        if (abs(change.difference) * 10).rounded() == 0 {
            return "No change over \(elapsed)"
        }
        let sign = change.difference > 0 ? "+" : "−"
        return "\(sign)\(magnitude) over \(elapsed)"
    }

    // MARK: - Percentile

    private struct PercentileReading {
        let label: String
        /// 0–1 along the band; below the 3rd pins to the left edge.
        let position: Double
        let median: String
        let source: String
    }

    private func percentileReading(value: Double, unit: MeasurementUnit, ageMonths: Double) -> PercentileReading? {
        guard let person, ageMonths <= GrowthPercentiles.maxAgeMonths,
              let row = GrowthPercentiles.percentileRow(
                ageMonths: ageMonths,
                gender: person.gender,
                type: measurement.measurementType
              ),
              let label = GrowthPercentiles.percentileLabel(
                value: value,
                unit: unit,
                ageMonths: ageMonths,
                gender: person.gender,
                type: measurement.measurementType
              ) else { return nil }

        let position: Double
        switch GrowthPercentiles.approximateRank(metricValue: MeasurementConversion.toMetric(value, from: unit), in: row) {
        case .below: position = 0
        case .value(let rank): position = rank / 100
        }
        let median = MeasurementConversion.fromMetric(row.p50, to: unit)
        return PercentileReading(
            label: label,
            position: position,
            median: MeasurementConversion.format(median, unit: unit, ageMonths: ageMonths),
            source: ageMonths <= GrowthPercentiles.whoCutoffMonths ? "WHO growth standards" : "CDC growth charts"
        )
    }

    private var percentile: PercentileReading? {
        guard let ageMonths else { return nil }
        return percentileReading(value: measurement.value, unit: measurement.unit, ageMonths: ageMonths)
    }

    /// Last time's percentile, so a jump between bands is visible without opening the other record.
    private var previousPercentileLabel: String? {
        guard let previous = change?.previous, let birthday = person?.birthday else { return nil }
        let months = GrowthPercentiles.ageInMonths(birthday: birthday, on: previous.date)
        guard months >= 0 else { return nil }
        return percentileReading(value: previous.value, unit: previous.unit, ageMonths: months)?.label
    }

    @ViewBuilder
    private var percentileSection: some View {
        if let percentile {
            VStack(alignment: .leading, spacing: 8) {
                Text("Percentile")
                    .font(.headline)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(percentile.label)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                            if let previousPercentileLabel {
                                Text("Last time \(previousPercentileLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        PercentileBand(position: percentile.position, tint: measurement.measurementType.color)

                        DetailFieldRow(label: "Median for age", value: percentile.median)

                        Text("Compared with \(percentile.source) for \(genderNoun) the same age.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var genderNoun: String {
        switch person?.gender ?? .other {
        case .male: return "boys"
        case .female: return "girls"
        default: return "children"
        }
    }

    // MARK: - Family

    private var comparisonPeople: [UUID: Person] {
        Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var comparisons: [GrowthComparison.Entry] {
        guard let person, let birthday = person.birthday, ageMonths != nil else { return [] }
        return GrowthComparison.compare(
            target: GrowthComparison.Sample(measurement),
            targetBirthday: birthday,
            targetPersonId: person.id,
            among: people.map { GrowthComparison.Candidate($0, type: measurement.measurementType) }
        )
    }

    @ViewBuilder
    private var familySection: some View {
        if let person, !person.isPregnancy {
            VStack(alignment: .leading, spacing: 12) {
                Text("Compared to Family")
                    .font(.headline)

                if person.birthday == nil {
                    familyNote("Add a birthday for \(person.name) to see percentiles and how they compare to the rest of the family.")
                } else {
                    familyComparisons(for: person)
                }
            }
        }
    }

    @ViewBuilder
    private func familyComparisons(for person: Person) -> some View {
        let entries = comparisons
        let byId = comparisonPeople
        let matched = entries.filter { !$0.hasNoRecords }
        let unmeasured = entries.filter { $0.hasNoRecords }.compactMap { byId[$0.personId]?.name }
        let groups = GrowthComparison.group(
            matched,
            subjectRemoteId: person.remoteId.flatMap(Int.init),
            remoteIds: byId.compactMapValues { $0.remoteId.flatMap(Int.init) },
            relations: relations.map(\.edge)
        )

        if groups.isEmpty {
            familyNote(entries.isEmpty
                ? "No one else in the family has a birthday set yet."
                : "No one else in the family was measured near this age or reached this \(typeNoun).")
        }

        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 8) {
                Text(group.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(group.entries) { entry in
                    if let relative = byId[entry.personId] {
                        FamilyComparisonCard(
                            relative: relative,
                            entry: entry,
                            subjectName: person.name,
                            measurementType: measurement.measurementType
                        )
                    }
                }
            }
        }

        if !unmeasured.isEmpty {
            Text("No \(typeNoun) recorded yet for \(ListFormatter.localizedString(byJoining: unmeasured)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func familyNote(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where a percentile falls between the 3rd and 97th, with the reference bands marked.
private struct PercentileBand: View {
    let position: Double
    let tint: Color

    private static let marks: [Double] = [3, 15, 50, 85, 97]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.15))
                        .frame(height: 8)
                    // The middle band, 15th to 85th, where most children sit.
                    Capsule()
                        .fill(tint.opacity(0.25))
                        .frame(width: width * 0.70, height: 8)
                        .offset(x: width * 0.15)
                    ForEach(Self.marks, id: \.self) { mark in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 1, height: 12)
                            .offset(x: width * mark / 100)
                    }
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: min(max(width * position - 8, 0), width - 16))
                }
            }
            .frame(height: 16)

            HStack {
                Text("3rd")
                Spacer()
                Text("50th")
                Spacer()
                Text("97th")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        // The label above already says the percentile in words.
        .accessibilityHidden(true)
    }
}

/// One relative against the measurement being viewed: what they measured at this age, and when they reached this value.
private struct FamilyComparisonCard: View {
    let relative: Person
    let entry: GrowthComparison.Entry
    let subjectName: String
    let measurementType: MeasurementType

    private func format(_ point: GrowthComparison.Point) -> String {
        MeasurementConversion.format(point.value, unit: point.unit, ageMonths: point.ageMonths)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    PersonAvatarView(person: relative, size: 32)
                    Text(relative.name)
                        .font(.headline)
                    Spacer()
                    if let relationship = relative.relationship {
                        Text(relationship.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let point = entry.atSameAge {
                    comparisonLine(
                        icon: "calendar",
                        title: "At \(point.ageLabel): \(format(point))",
                        detail: GrowthComparison.describeValue(point, type: measurementType, subject: subjectName)
                    )
                }

                if let point = entry.atSameValue {
                    comparisonLine(
                        icon: "scope",
                        title: "Reached \(format(point)) at \(point.ageLabel)",
                        detail: "\(GrowthComparison.describeAge(point, subject: subjectName)) · \(point.date.formatted(date: .abbreviated, time: .omitted))"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func comparisonLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(measurementType.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

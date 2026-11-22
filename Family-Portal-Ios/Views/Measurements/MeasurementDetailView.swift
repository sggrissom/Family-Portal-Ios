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
    @Environment(AuthService.self) private var authService
    @State private var isEditing = false
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                MeasurementInsightsView(measurement: measurement)
                    .padding()
            }
            .navigationTitle("Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A view-only member reads the measurement and nothing more.
                if authService.access.canContribute(to: measurement) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSharing = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Copy.share.action)
                }
            }
            .sheet(isPresented: $isEditing) {
                EditMeasurementView(measurement: measurement)
            }
            .sheet(isPresented: $isSharing) {
                MeasurementShareSheet(measurements: [measurement])
            }
        }
    }
}

/// The body of a measurement's page — its value, facts, percentile and the family comparison — shared by the detail sheet and the checkup's result screen, so a measurement reads the same wherever it was just saved or later opened.
struct MeasurementInsightsView: View {
    let measurement: GrowthData
    /// Off on a checkup's result, which shows one strip for both of its values rather than one each.
    var showsSameAge = true

    /// The whole roster and graph, for the family comparison. A sheet can't narrow a `@Query` to one family any better than the add sheets can, and the store only ever holds the signed-in family.
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]

    private var reading: MeasurementReading { MeasurementReading(measurement: measurement) }
    private var person: Person? { measurement.person }

    var body: some View {
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
            if showsSameAge {
                PersonSameAgeStrip(person: measurement.person, date: measurement.date)
            }
        }
    }

    // MARK: - Facts

    private var facts: some View {
        DetailFieldGroup {
            DetailFieldRow(
                label: "Date",
                value: measurement.date.displayDay().formatted(date: .long, time: .omitted)
            )

            if let person {
                Divider()
                DetailFieldRow(label: "Person", value: person.name)

                if let age = person.age(on: measurement.date) {
                    Divider()
                    DetailFieldRow(label: "Age", value: age)
                }
            }

            if let alternateValue = reading.alternateValue {
                Divider()
                DetailFieldRow(label: alternateValue.label, value: alternateValue.value)
            }

            if let change = reading.change {
                Divider()
                DetailFieldRow(label: "Since last", value: reading.changeText(change))
            }
        }
    }

    // MARK: - Percentile

    @ViewBuilder
    private var percentileSection: some View {
        if let percentile = reading.percentile {
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
                            if let previousPercentileLabel = reading.previousPercentileLabel {
                                Text("Last time \(previousPercentileLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        PercentileBand(position: percentile.position, tint: measurement.measurementType.color)

                        DetailFieldRow(label: "Median for age", value: percentile.median)

                        Text(reading.percentileSourceText(percentile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Family

    @ViewBuilder
    private var familySection: some View {
        if let person, !person.isPregnancy {
            ContextSection("Compared to Family", kind: .family) {
                VStack(alignment: .leading, spacing: 12) {
                    if person.birthday == nil {
                        familyNote("Add a birthday for \(person.name) to see percentiles and how they compare to the rest of the family.")
                    } else if let family = reading.family(people: people, relations: relations) {
                        familyComparisons(family, for: person)
                    } else {
                        familyNote("No one else in the family has a birthday set yet.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func familyComparisons(_ family: MeasurementReading.Family, for person: Person) -> some View {
        if family.groups.isEmpty {
            familyNote(family.entries.isEmpty
                ? "No one else in the family has a birthday set yet."
                : "No one else in the family was measured near this age or reached this \(reading.typeNoun).")
        }

        ForEach(family.groups) { group in
            VStack(alignment: .leading, spacing: 8) {
                Text(group.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(group.entries) { entry in
                    if let relative = family.peopleById[entry.personId] {
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

        if !family.unmeasuredNames.isEmpty {
            Text("No \(reading.typeNoun) recorded yet for \(ListFormatter.localizedString(byJoining: family.unmeasuredNames)).")
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
                        title: MeasurementReading.sameAgeTitle(point),
                        detail: MeasurementReading.sameAgeDetail(point, type: measurementType, subject: subjectName)
                    )
                }

                if let point = entry.atSameValue {
                    comparisonLine(
                        icon: "scope",
                        title: MeasurementReading.sameValueTitle(point),
                        detail: MeasurementReading.sameValueDetail(point, subject: subjectName)
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

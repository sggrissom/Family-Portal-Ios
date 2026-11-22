import Foundation

/// What a measurement's page says about it past the value: the change since last time, its percentile, and how the family measured at the same age. Shared by the page and its share card so the two read the same.
struct MeasurementReading {
    let measurement: GrowthData

    struct Percentile {
        let label: String
        /// 0–1 along the band; below the 3rd pins to the left edge.
        let position: Double
        let median: String
        let source: String
    }

    var person: Person? { measurement.person }
    var ageMonths: Double? { MeasurementConversion.ageMonths(of: measurement) }
    var typeNoun: String { measurement.measurementType.rawValue }

    var alternateValue: (label: String, value: String)? {
        guard let other = measurement.measurementType.validUnits.first(where: { $0 != measurement.unit }) else {
            return nil
        }
        let converted = MeasurementConversion.convert(measurement.value, from: measurement.unit, to: other)
        return ("In \(other.rawValue)", MeasurementConversion.format(converted, unit: other, ageMonths: ageMonths))
    }

    // MARK: - Since last

    var change: GrowthComparison.Change? {
        let samples = (person?.growthData ?? [])
            .filter { $0.measurementType == measurement.measurementType && $0.id != measurement.id }
            .map { GrowthComparison.Sample($0) }
        return GrowthComparison.change(from: samples, to: GrowthComparison.Sample(measurement))
    }

    /// "+1.2 in over 3 wk", in this record's unit whatever the last one was entered in.
    func changeText(_ change: GrowthComparison.Change) -> String {
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

    func percentileReading(value: Double, unit: MeasurementUnit, ageMonths: Double) -> Percentile? {
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
        return Percentile(
            label: label,
            position: position,
            median: MeasurementConversion.format(median, unit: unit, ageMonths: ageMonths),
            source: ageMonths <= GrowthPercentiles.whoCutoffMonths ? "WHO growth standards" : "CDC growth charts"
        )
    }

    var percentile: Percentile? {
        guard let ageMonths else { return nil }
        return percentileReading(value: measurement.value, unit: measurement.unit, ageMonths: ageMonths)
    }

    var previousPercentileLabel: String? {
        guard let previous = change?.previous, let birthday = person?.birthday else { return nil }
        let months = GrowthPercentiles.ageInMonths(birthday: birthday, on: previous.date)
        guard months >= 0 else { return nil }
        return percentileReading(value: previous.value, unit: previous.unit, ageMonths: months)?.label
    }

    var genderNoun: String {
        switch person?.gender ?? .other {
        case .male: return "boys"
        case .female: return "girls"
        default: return "children"
        }
    }

    func percentileSourceText(_ percentile: Percentile) -> String {
        "Compared with \(percentile.source) for \(genderNoun) the same age."
    }

    // MARK: - Family

    struct Family {
        let groups: [GrowthComparison.Group]
        /// Everyone compared, matched or not.
        let entries: [GrowthComparison.Entry]
        let unmeasuredNames: [String]
        let peopleById: [UUID: Person]
    }

    func family(people: [Person], relations: [PersonRelation]) -> Family? {
        guard let person, !person.isPregnancy, let birthday = person.birthday, ageMonths != nil else { return nil }
        let byId = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = GrowthComparison.compare(
            target: GrowthComparison.Sample(measurement),
            targetBirthday: birthday,
            targetPersonId: person.id,
            among: people.map { GrowthComparison.Candidate($0, type: measurement.measurementType) }
        )
        let matched = entries.filter { !$0.hasNoRecords }
        let groups = GrowthComparison.group(
            matched,
            subjectRemoteId: person.serverId,
            remoteIds: byId.compactMapValues { $0.serverId },
            relations: relations.map(\.edge)
        )
        return Family(
            groups: groups,
            entries: entries,
            unmeasuredNames: entries.filter(\.hasNoRecords).compactMap { byId[$0.personId]?.name },
            peopleById: byId
        )
    }

    // MARK: - A relative's lines

    static func format(_ point: GrowthComparison.Point) -> String {
        MeasurementConversion.format(point.value, unit: point.unit, ageMonths: point.ageMonths)
    }

    static func sameAgeTitle(_ point: GrowthComparison.Point) -> String {
        "At \(point.ageLabel): \(format(point))"
    }

    static func sameAgeDetail(_ point: GrowthComparison.Point, type: MeasurementType, subject: String) -> String {
        GrowthComparison.describeValue(point, type: type, subject: subject)
    }

    static func sameValueTitle(_ point: GrowthComparison.Point) -> String {
        "Reached \(format(point)) at \(point.ageLabel)"
    }

    static func sameValueDetail(_ point: GrowthComparison.Point, subject: String) -> String {
        "\(GrowthComparison.describeAge(point, subject: subject)) · \(point.date.displayDay().formatted(date: .abbreviated, time: .omitted))"
    }
}

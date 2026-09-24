import Foundation

/// How one measurement stands against the rest of the family's, ported from frontend/lib/growthComparison.ts so the detail sheet and the web's measurement page find the same matches.
/// Two questions per relative: what did they measure at this same age, and at what age did they reach this same value. A relative is only listed when one of the answers is close enough to be worth saying.
/// Works on plain values rather than `@Model`s, so it can be reasoned about — and tested — without a `ModelContainer`.
enum GrowthComparison {

    /// One recorded value, in whatever unit it was entered in.
    struct Sample: Equatable {
        let date: Date
        let value: Double
        let unit: MeasurementUnit
    }

    /// Someone whose records might be compared against, with only the records of the type being compared.
    struct Candidate {
        let id: UUID
        let birthday: Date?
        let isPregnancy: Bool
        let samples: [Sample]
    }

    /// One relative's record, set against the measurement being viewed.
    struct Point: Equatable {
        let ageMonths: Double
        let value: Double
        let unit: MeasurementUnit
        let date: Date
        /// The viewed value minus this one, in *this* point's unit. Positive means the viewed person was taller or heavier.
        let valueDiff: Double
        /// This point's age minus the viewed age. Positive means the relative got there later.
        let ageDiffMonths: Double

        var ageLabel: String { GrowthPercentiles.formatAge(months: ageMonths) }
    }

    struct Entry: Identifiable, Equatable {
        let personId: UUID
        let atSameAge: Point?
        let atSameValue: Point?

        var id: UUID { personId }
        /// A relative with no records of this type is still listed, so the sheet can say so rather than quietly leaving them out.
        var hasNoRecords: Bool { atSameAge == nil && atSameValue == nil }
    }

    // How close a match has to be before it is worth mentioning — the web's thresholds, so both clients list the same people.
    private static let ageToleranceRatio = 0.05
    private static let minimumAgeToleranceMonths = 0.5
    private static let valueToleranceRatio = 0.02

    private struct Aged {
        let ageMonths: Double
        let sample: Sample
    }

    /// `target` is the measurement being viewed; `targetBirthday` is its person's. Pregnancy records on either side are skipped, as is anyone without a birthday — an age is what the whole comparison hangs on.
    static func compare(
        target: Sample,
        targetBirthday: Date,
        targetPersonId: UUID,
        among candidates: [Candidate]
    ) -> [Entry] {
        let targetAge = GrowthPercentiles.ageInMonths(birthday: targetBirthday, on: target.date)
        let targetMetric = MeasurementConversion.toMetric(target.value, from: target.unit)

        var entries: [Entry] = []
        for candidate in candidates {
            guard candidate.id != targetPersonId, !candidate.isPregnancy,
                  let birthday = candidate.birthday else { continue }

            let aged: [Aged] = candidate.samples.map { sample in
                Aged(ageMonths: GrowthPercentiles.ageInMonths(birthday: birthday, on: sample.date), sample: sample)
            }
            guard !aged.isEmpty else {
                entries.append(Entry(personId: candidate.id, atSameAge: nil, atSameValue: nil))
                continue
            }

            let byAge = aged.min { abs($0.ageMonths - targetAge) < abs($1.ageMonths - targetAge) }
            let byValue = aged.min {
                abs(MeasurementConversion.toMetric($0.sample.value, from: $0.sample.unit) - targetMetric)
                    < abs(MeasurementConversion.toMetric($1.sample.value, from: $1.sample.unit) - targetMetric)
            }

            let ageTolerance = max(minimumAgeToleranceMonths, targetAge * ageToleranceRatio)
            let ageMatch: Aged? = byAge.flatMap { match in
                abs(match.ageMonths - targetAge) <= ageTolerance ? match : nil
            }
            let valueMatch: Aged? = byValue.flatMap { match in
                let metric = MeasurementConversion.toMetric(match.sample.value, from: match.sample.unit)
                return abs(metric - targetMetric) <= targetMetric * valueToleranceRatio ? match : nil
            }
            guard ageMatch != nil || valueMatch != nil else { continue }

            func point(_ match: Aged) -> Point {
                Point(
                    ageMonths: match.ageMonths,
                    value: match.sample.value,
                    unit: match.sample.unit,
                    date: match.sample.date,
                    valueDiff: MeasurementConversion.fromMetric(targetMetric, to: match.sample.unit) - match.sample.value,
                    ageDiffMonths: match.ageMonths - targetAge
                )
            }
            entries.append(Entry(
                personId: candidate.id,
                atSameAge: ageMatch.map { point($0) },
                atSameValue: valueMatch.map { point($0) }
            ))
        }
        return entries
    }

    // MARK: - Wording

    /// "Mia was 1.2 in taller at this age". `subject` is the person whose measurement is being viewed.
    static func describeValue(_ point: Point, type: MeasurementType, subject: String) -> String {
        let noun = type == .height ? "height" : "weight"
        if (abs(point.valueDiff) * 10).rounded() == 0 {
            return "\(subject) was about the same \(noun) at this age"
        }
        let comparative: String
        switch type {
        case .height: comparative = point.valueDiff > 0 ? "taller" : "shorter"
        case .weight: comparative = point.valueDiff > 0 ? "heavier" : "lighter"
        }
        return "\(subject) was \(formatDifference(point)) \(comparative) at this age"
    }

    /// "3 mo later than Mia" — whether the relative got to this value before or after the person being viewed did.
    static func describeAge(_ point: Point, subject: String) -> String {
        if abs(point.ageDiffMonths).rounded() < 1 {
            return "about the same age as \(subject)"
        }
        let duration = formatDuration(months: abs(point.ageDiffMonths))
        return point.ageDiffMonths > 0 ? "\(duration) later than \(subject)" : "\(duration) earlier than \(subject)"
    }

    /// The gap between two values, unsigned, in the point's unit — pounds and ounces for a baby's weight, same as the value itself.
    static func formatDifference(_ point: Point) -> String {
        formatMagnitude(abs(point.valueDiff), unit: point.unit, ageMonths: point.ageMonths)
    }

    static func formatMagnitude(_ magnitude: Double, unit: MeasurementUnit, ageMonths: Double?) -> String {
        if MeasurementConversion.prefersPoundsAndOunces(magnitude, unit: unit, ageMonths: ageMonths) {
            return MeasurementConversion.formatPoundsAndOunces(magnitude)
        }
        return "\(MeasurementConversion.oneDecimal(magnitude)) \(MeasurementConversion.abbreviation(unit))"
    }

    static func formatDuration(months: Double) -> String {
        let total = Int(months.rounded())
        if total < 12 { return "\(total) mo" }
        let years = total / 12
        let remainder = total % 12
        if remainder == 0 { return "\(years) yr" }
        return "\(years) yr \(remainder) mo"
    }

    // MARK: - Grouping

    struct Group: Identifiable {
        let title: String
        let entries: [Entry]

        var id: String { title }
    }

    /// Siblings, then parents, then everyone else — the web's order. Read off the locally held relation graph rather than the server's labels, so the sheet groups the same way offline.
    /// `subjectRemoteId` is `nil` for a person still uploading, who has no edges yet; everyone then falls to the last group, which is simply titled "Family" when it is the only one.
    static func group(
        _ entries: [Entry],
        subjectRemoteId: Int?,
        remoteIds: [UUID: Int],
        relations: [RelationEdge]
    ) -> [Group] {
        let siblingIds = subjectRemoteId.map { Set(RelationGraph.siblings(relations, of: $0)) } ?? []
        let parentIds = subjectRemoteId.map { Set(RelationGraph.parents(relations, of: $0)) } ?? []

        var siblings: [Entry] = []
        var parents: [Entry] = []
        var others: [Entry] = []
        for entry in entries {
            let remoteId = remoteIds[entry.personId]
            if let remoteId, siblingIds.contains(remoteId) {
                siblings.append(entry)
            } else if let remoteId, parentIds.contains(remoteId) {
                parents.append(entry)
            } else {
                others.append(entry)
            }
        }

        var groups: [Group] = []
        if !siblings.isEmpty { groups.append(Group(title: "Siblings", entries: siblings)) }
        if !parents.isEmpty { groups.append(Group(title: "Parents", entries: parents)) }
        if !others.isEmpty {
            groups.append(Group(title: groups.isEmpty ? "Family" : "Rest of the family", entries: others))
        }
        return groups
    }

    // MARK: - Since the last measurement

    struct Change: Equatable {
        let previous: Sample
        /// This value minus the previous one, in this value's unit.
        let difference: Double
        let elapsedDays: Int
    }

    /// The change from the latest earlier record of the same type. `nil` for someone's first measurement.
    static func change(from samples: [Sample], to target: Sample, calendar: Calendar = .current) -> Change? {
        guard let previous = samples
            .filter({ $0.date < target.date })
            .max(by: { $0.date < $1.date }) else { return nil }

        let previousInTargetUnit = MeasurementConversion.convert(previous.value, from: previous.unit, to: target.unit)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: previous.date),
            to: calendar.startOfDay(for: target.date)
        ).day ?? 0
        return Change(previous: previous, difference: target.value - previousInTargetUnit, elapsedDays: days)
    }

    /// "12 days", "3 wk", "5 mo", "1 yr 2 mo" — newborns are weighed days apart, so short gaps keep their precision.
    static func formatElapsed(days: Int) -> String {
        if days < 14 { return days == 1 ? "1 day" : "\(days) days" }
        if days < 61 { return "\(Int((Double(days) / 7).rounded())) wk" }
        return formatDuration(months: Double(days) / 30.4375)
    }
}

extension GrowthComparison.Sample {
    init(_ record: GrowthData) {
        self.init(date: record.date, value: record.value, unit: record.unit)
    }
}

extension GrowthComparison.Candidate {
    init(_ person: Person, type: MeasurementType) {
        self.init(
            id: person.id,
            birthday: person.birthday,
            isPregnancy: person.isPregnancy,
            samples: person.growthData
                .filter { $0.measurementType == type }
                .map { GrowthComparison.Sample($0) }
        )
    }
}

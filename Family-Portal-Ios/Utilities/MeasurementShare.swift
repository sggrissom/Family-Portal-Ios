import Foundation

/// What a measurement's share card and copied text carry: the values and the comparisons its page shows, in the page's order, and nothing else of the person's record.
struct MeasurementShare: Equatable {

    struct Line: Equatable {
        let title: String
        let detail: String?
    }

    struct Row: Identifiable, Equatable {
        let id: String
        /// The family group a relative's row sits under on the page ("Siblings"); `nil` for the measurement's own rows.
        let group: String?
        let heading: String
        let lines: [Line]
    }

    struct Section: Identifiable, Equatable {
        let id: UUID
        let type: MeasurementType
        let value: String
        let alternate: String?
        var rows: [Row]
    }

    let personName: String
    let dateText: String
    let ageText: String?
    var sections: [Section]

    var rowIds: [String] { sections.flatMap { $0.rows.map(\.id) } }

    func omitting(_ ids: Set<String>) -> MeasurementShare {
        var copy = self
        copy.sections = sections.map { section in
            var section = section
            section.rows = section.rows.filter { !ids.contains($0.id) }
            return section
        }
        return copy
    }

    var text: String {
        var lines = [[personName, dateText, ageText].compactMap { $0 }.joined(separator: " · ")]
        for section in sections {
            lines.append("")
            let value = section.alternate.map { "\(section.value) (\($0))" } ?? section.value
            lines.append("\(section.type.label): \(value)")
            var group: String?
            for row in section.rows {
                if let rowGroup = row.group, rowGroup != group {
                    lines.append("\(rowGroup):")
                }
                group = row.group
                let body = row.lines
                    .map { line in line.detail.map { "\(line.title) — \($0)" } ?? line.title }
                    .joined(separator: "; ")
                lines.append("• \(row.heading): \(body)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension MeasurementShare {

    /// One person's measurements from one day — a checkup's height and weight, or a single record. `nil` with nothing to share.
    init?(measurements: [GrowthData], people: [Person], relations: [PersonRelation]) {
        guard let first = measurements.first else { return nil }
        let person = first.person
        self.init(
            personName: person?.name ?? "",
            dateText: first.date.displayDay().formatted(date: .long, time: .omitted),
            ageText: person?.age(on: first.date),
            sections: measurements.map { Self.section($0, people: people, relations: relations) }
        )
    }

    private static func section(_ measurement: GrowthData, people: [Person], relations: [PersonRelation]) -> Section {
        let reading = MeasurementReading(measurement: measurement)
        let key = measurement.id.uuidString
        var rows: [Row] = []

        if let change = reading.change {
            rows.append(Row(id: "\(key)-since", group: nil, heading: "Since last", lines: [
                Line(title: reading.changeText(change), detail: nil),
            ]))
        }

        if let percentile = reading.percentile {
            rows.append(Row(id: "\(key)-percentile", group: nil, heading: "Percentile", lines: [
                Line(title: percentile.label, detail: reading.previousPercentileLabel.map { "Last time \($0)" }),
                Line(title: "Median for age \(percentile.median)", detail: reading.percentileSourceText(percentile)),
            ]))
        }

        if let family = reading.family(people: people, relations: relations) {
            let subject = measurement.person?.name ?? ""
            for group in family.groups {
                for entry in group.entries {
                    guard let relative = family.peopleById[entry.personId] else { continue }
                    var lines: [Line] = []
                    if let point = entry.atSameAge {
                        lines.append(Line(
                            title: MeasurementReading.sameAgeTitle(point),
                            detail: MeasurementReading.sameAgeDetail(point, type: measurement.measurementType, subject: subject)
                        ))
                    }
                    if let point = entry.atSameValue {
                        lines.append(Line(
                            title: MeasurementReading.sameValueTitle(point),
                            detail: MeasurementReading.sameValueDetail(point, subject: subject)
                        ))
                    }
                    let heading = [relative.name, relative.relationship?.capitalized]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    rows.append(Row(id: "\(key)-\(relative.id.uuidString)", group: group.title, heading: heading, lines: lines))
                }
            }
        }

        return Section(
            id: measurement.id,
            type: measurement.measurementType,
            value: MeasurementConversion.format(measurement),
            alternate: reading.alternateValue?.value,
            rows: rows
        )
    }
}

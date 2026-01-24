import Foundation

enum PersonType: String, Codable, CaseIterable {
    case parent
    case child
}

enum Gender: String, Codable, CaseIterable {
    case male
    case female
    case other
}

enum MeasurementType: String, Codable, CaseIterable {
    case height
    case weight

    var validUnits: [MeasurementUnit] {
        MeasurementUnit.units(for: self)
    }

    var defaultUnit: MeasurementUnit {
        MeasurementUnit.defaultUnit(for: self)
    }
}

enum MeasurementUnit: String, Codable, CaseIterable {
    case inches
    case centimeters
    case pounds
    case kilograms

    static func units(for type: MeasurementType) -> [MeasurementUnit] {
        switch type {
        case .height:
            return [.inches, .centimeters]
        case .weight:
            return [.pounds, .kilograms]
        }
    }

    static func defaultUnit(for type: MeasurementType) -> MeasurementUnit {
        switch type {
        case .height:
            return .inches
        case .weight:
            return .pounds
        }
    }
}

enum MilestoneCategory: String, Codable, CaseIterable {
    case development
    case behavior
    case health
    case achievement
    case first
    case other
}

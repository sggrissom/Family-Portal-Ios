import Foundation

/// How a relationship is phrased when it is entered: the value names what the new person is to the anchor, so the direction travels on the wire and the server never has to guess which way round it was said. Mirrors `StatedRelation` in backend/relation.go, whose iota order these raw values pin.
nonisolated enum StatedRelation: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case child = 1
    case parent = 2
    case sibling = 3
    case partner = 4
}

/// The three edges the graph actually stores, mirroring `RelationKind` in backend/relation.go whose iota order these raw values pin. Everything else the app shows — grandmother, cousin, stepson — is the server walking these outward.
/// A parent edge is directed, `fromId` being the parent. Sibling and partner edges are symmetric and arrive in whichever direction they were first stated, so nothing may read meaning into which end is which.
nonisolated enum RelationKind: Int, Codable, CaseIterable, Sendable {
    case parent = 0
    case sibling = 1
    case partner = 2
}

/// One wording offered when stating a relationship, mirroring `RELATION_OPTIONS` in frontend/lib/routeHelpers.ts so both clients offer the same words. A gendered word also fills in the new person's gender: "daughter" has already said it.
struct RelationOption: Identifiable, Hashable {
    let label: String
    let stated: StatedRelation
    let gender: Gender?

    var id: String { "\(stated.rawValue)-\(label)" }

    static let all: [RelationOption] = [
        RelationOption(label: "daughter", stated: .child, gender: .female),
        RelationOption(label: "son", stated: .child, gender: .male),
        RelationOption(label: "child", stated: .child, gender: nil),
        RelationOption(label: "mother", stated: .parent, gender: .female),
        RelationOption(label: "father", stated: .parent, gender: .male),
        RelationOption(label: "parent", stated: .parent, gender: nil),
        RelationOption(label: "sister", stated: .sibling, gender: .female),
        RelationOption(label: "brother", stated: .sibling, gender: .male),
        RelationOption(label: "sibling", stated: .sibling, gender: nil),
        RelationOption(label: "wife", stated: .partner, gender: .female),
        RelationOption(label: "husband", stated: .partner, gender: .male),
        RelationOption(label: "partner", stated: .partner, gender: nil),
    ]
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

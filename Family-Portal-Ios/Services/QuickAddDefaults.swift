import Foundation

/// What an add sheet opens with when nobody told it.
///
/// A quick-add that opens on "choose someone" has moved the taps rather than
/// removed them, and a household that works in pounds should not be handed
/// kilograms every time.
struct QuickAddDefaults {
    private static let personKey = "com.familyrecord.quickAdd.personId"
    private static let measurementTypeKey = "com.familyrecord.quickAdd.measurementType"
    private static let measurementUnitKey = "com.familyrecord.quickAdd.measurementUnit"
    private static let unitPrefsKey = "com.familyrecord.quickAdd.unitPrefs"

    private let defaults: UserDefaults

    /// Injectable so tests use a scratch suite, the way `SyncQueue` and `LocalAccountOwner` do.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Person

    var rememberedPersonId: UUID? {
        guard let raw = defaults.string(forKey: Self.personKey) else { return nil }
        return UUID(uuidString: raw)
    }

    func rememberPerson(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Self.personKey)
    }

    // MARK: - Measurement

    var rememberedMeasurementType: MeasurementType? {
        defaults.string(forKey: Self.measurementTypeKey).flatMap(MeasurementType.init(rawValue:))
    }

    func rememberMeasurement(type: MeasurementType, unit: MeasurementUnit) {
        defaults.set(type.rawValue, forKey: Self.measurementTypeKey)
        defaults.set(unit.rawValue, forKey: Self.measurementUnitKey)
    }

    /// The unit to open on for `type`. The remembered one only when it is valid for that type — a height last taken in inches says nothing about how this family weighs anybody.
    func unit(for type: MeasurementType) -> MeasurementUnit {
        guard let raw = defaults.string(forKey: Self.measurementUnitKey),
              let remembered = MeasurementUnit(rawValue: raw),
              type.validUnits.contains(remembered) else {
            return type.defaultUnit
        }
        return remembered
    }

    // MARK: - Checkup units

    /// Units per person, then for the family — what the checkup opens on. Keyed by local person id, like the remembered person, so an erase needs no sweep: an id nobody holds any more is simply never asked for.
    var unitPrefs: UnitPrefs {
        guard let data = defaults.data(forKey: Self.unitPrefsKey),
              let prefs = try? JSONDecoder().decode(UnitPrefs.self, from: data) else {
            return legacyUnitPrefs
        }
        return prefs
    }

    func saveUnitPrefs(_ prefs: UnitPrefs) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: Self.unitPrefsKey)
    }

    /// A device that only ever used the one-type sheet remembered a single unit. It seeds the family default for the type it can measure — never the other, for the reason `unit(for:)` gives.
    private var legacyUnitPrefs: UnitPrefs {
        var prefs = UnitPrefs()
        guard let raw = defaults.string(forKey: Self.measurementUnitKey),
              let unit = MeasurementUnit(rawValue: raw) else { return prefs }
        switch unit {
        case .centimeters: prefs.lastHeight = .centimeters
        case .inches: prefs.lastHeight = .inches
        case .kilograms: prefs.lastWeight = .kilograms
        case .pounds: prefs.lastWeight = .pounds
        }
        return prefs
    }

    // MARK: - Resolving a person

    /// Who a sheet opens on when the caller did not name anybody:
    ///
    /// 1. the person last written for, **if the roster still holds them** — an
    ///    id outlives an account erase, and a record landing on whoever inherited
    ///    that slot would be silent and wrong, so an unrecognised id resolves to
    ///    nobody rather than to somebody arbitrary;
    /// 2. the only person, when there is one;
    /// 3. the first of the youngest generation. `FamilyGroups` bands the roster
    ///    from the bottom, so its last generation is always the "Children" one,
    ///    which is who a family logs.
    ///
    /// A household that has stated no relationships at all has no youngest band
    /// and gets **nil** — the sheet asks, and remembers the answer for next time.
    static func person(in people: [Person], remembered: UUID?, relations: [RelationEdge]) -> Person? {
        if let remembered, let match = people.first(where: { $0.id == remembered }) {
            return match
        }
        if people.count == 1 {
            return people.first
        }
        let generations = FamilyGroups.group(people: people, relations: relations)
            .filter { $0.key.hasPrefix("generation-") }
        return generations.last?.people.first
    }
}

import OSLog
import SwiftUI
import SwiftData

/// One checkup: a height and a weight for one person on one day, either of which may be blank — a port of the web's measurement form over `Checkup`.
/// Save queues one `AddGrowthData` per filled field and moves on to the result screen, which replaced **Save and Add Another**: height and weight are now one trip, and the result screen's **Add another measurement** covers the next person.
struct AddMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?

    /// The whole roster rather than one person: a `@Query` predicate cannot follow a `@State` selection.
    @Query(sort: \Person.name) private var people: [Person]
    /// For the fallback in `QuickAddDefaults.person`, which bands the roster to find the youngest generation.
    @Query private var relations: [PersonRelation]

    private let defaults = QuickAddDefaults()

    @State private var selectedPersonId: UUID?
    @State private var when = WhenEntry()
    @State private var entry = CheckupEntry()
    @State private var error: String?
    @State private var isSaving = false
    @State private var result: CheckupResult?
    /// The person the units were last defaulted for, so switching person re-defaults units but a re-render does not undo a unit the user just picked.
    @State private var unitsFor: UUID?
    @FocusState private var focusedField: Field?
    /// Its own focus state because `PoundsAndOuncesFields` takes a `Bool` binding.
    @FocusState private var isPoundsFocused: Bool

    private enum Field: Hashable { case height, feet, weight }

    private var person: Person? {
        people.first { $0.id == selectedPersonId }
    }

    /// The day being recorded, for the age line and the units. Falls back to today while the entry has a problem.
    private var date: Date {
        when.resolvedDate(birthday: person?.birthday) ?? Date()
    }

    /// `nil` opens the form with the remembered person preselected, as a visible chip. A caller standing on somebody names them.
    init(personId: UUID? = nil) {
        _selectedPersonId = State(initialValue: personId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Copy.measurement.who) {
                    PersonChips(selection: $selectedPersonId)
                    if let person, let age = person.age(on: date) {
                        Text("\(person.name) · \(age)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    WhenControl(entry: $when, birthday: person?.birthday)
                        .id(person?.id)
                }

                heightSection
                weightSection

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(Copy.measurement.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.measurement.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? Copy.measurement.saving : Copy.measurement.save) { save() }
                        .disabled(isSaving)
                }
            }
            .navigationDestination(item: $result) { result in
                CheckupResultView(
                    result: result,
                    onAddAnother: addAnother,
                    onDone: { dismiss() }
                )
            }
            .onAppear {
                if selectedPersonId == nil {
                    selectedPersonId = QuickAddDefaults.person(
                        in: people,
                        remembered: defaults.rememberedPersonId,
                        relations: relations.map(\.edge)
                    )?.id
                }
                defaultUnits()
            }
            .onChange(of: selectedPersonId) { _, _ in
                error = nil
                defaultUnits()
            }
        }
    }

    // MARK: - Sections

    private var heightSection: some View {
        Section {
            Picker(Copy.measurement.heightUnit, selection: $entry.heightUnit) {
                ForEach(CheckupHeightUnit.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if entry.heightUnit == .feetInches {
                HStack {
                    TextField(Copy.measurement.feet, text: $entry.feet)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .feet)
                    TextField(Copy.measurement.inches, text: $entry.inches)
                        .keyboardType(.decimalPad)
                }
            } else {
                TextField(Copy.measurement.height, text: $entry.height)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .height)
            }
        } header: {
            Text(Copy.measurement.height)
        } footer: {
            helper(for: .height)
        }
    }

    private var weightSection: some View {
        Section {
            Picker(Copy.measurement.weightUnit, selection: $entry.weightUnit) {
                ForEach(CheckupWeightUnit.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if entry.weightUnit == .poundsOunces {
                PoundsAndOuncesFields(
                    pounds: $entry.pounds,
                    ounces: $entry.ounces,
                    isPoundsFocused: $isPoundsFocused
                )
            } else {
                TextField(Copy.measurement.weight, text: $entry.weight)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
            }
        } header: {
            Text(Copy.measurement.weight)
        } footer: {
            helper(for: .weight)
        }
    }

    /// "last: 3 ft 1.75 in, 4 months ago" — persistent, so the number being typed can be checked against the last one.
    @ViewBuilder
    private func helper(for type: MeasurementType) -> some View {
        if let person {
            let last = Checkup.latest(of: person.growthData, type: type)
            let text = Checkup.describeLast(last, ageMonthsThen: last.flatMap { MeasurementConversion.ageMonths(of: $0) }, now: Date())
            if !text.isEmpty {
                Text(text)
            }
        }
    }

    // MARK: - Units

    private func defaultUnits() {
        guard let person, unitsFor != person.id else { return }
        unitsFor = person.id
        let prefs = defaults.unitPrefs
        let key = person.id.uuidString
        let ageMonths = person.birthday.map { AgeSteps.monthsOld(birthday: $0, at: date) }
        entry.heightUnit = Checkup.defaultHeightUnit(prefs, personKey: key, personGrowth: person.growthData)
        entry.weightUnit = Checkup.defaultWeightUnit(prefs, personKey: key, ageMonths: person.isPregnancy ? nil : ageMonths)
    }

    // MARK: - Saving

    private func save() {
        guard let person else {
            error = Copy.measurement.pickPerson
            return
        }
        if let problem = when.problem {
            error = problem
            return
        }
        let checked = Checkup.measurements(entry)
        if let problem = checked.error {
            error = problem
            return
        }
        guard let date = when.resolvedDate(birthday: person.birthday) else {
            error = "Enter an age in years"
            return
        }

        error = nil
        isSaving = true
        defaults.rememberPerson(person.id)
        defaults.saveUnitPrefs(Checkup.remember(defaults.unitPrefs, personKey: person.id.uuidString, measurements: checked.measurements, entry: entry))

        let records = checked.measurements.map { measurement -> GrowthData in
            let record = GrowthData(measurementType: measurement.type, value: measurement.value, unit: measurement.unit, date: date)
            record.person = person
            modelContext.insert(record)
            return record
        }

        Task {
            var failed = Set<UUID>()
            // One enqueue per field, each on its own: a weight that fails to queue must not take the height with it.
            for record in records {
                do {
                    try await syncService?.addGrowthData(record, for: person)
                } catch {
                    AppLog.ui.error("Couldn't queue measurement: \(String(describing: error), privacy: .public)")
                    failed.insert(record.id)
                }
            }
            isSaving = false
            result = CheckupResult(personId: person.id, recordIds: records.map(\.id), failedIds: failed)
        }
    }

    /// The same form again, with the person cleared and the day kept — the next child at the same checkup.
    private func addAnother() {
        result = nil
        entry = entry.cleared()
        selectedPersonId = nil
        unitsFor = nil
    }
}

/// What a checkup saved, carried to the result screen by id so the screen reads the live records — their sync state changes while it is up.
struct CheckupResult: Hashable, Identifiable {
    let personId: UUID
    let recordIds: [UUID]
    /// Records whose enqueue threw. Shown as not saved, each retryable on its own.
    var failedIds: Set<UUID>

    var id: [UUID] { recordIds }
}

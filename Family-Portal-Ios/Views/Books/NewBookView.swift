import SwiftData
import SwiftUI

/// Starting a book — the web's `/new-book` (`frontend/pages/books/new-book.tsx`). Who and when, what to include, a title; then the server gathers the records, the device drafts the book exactly as the web would, and the draft is saved and opened.
struct NewBookView: View {
    let preset: BookPlans.Preset
    let onCreated: @MainActor (BookDTO) -> Void

    @Environment(BookService.self) private var service
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var personIds: [Int] = []
    @State private var yearKind: BookPlans.YearKind = .calendar
    @State private var year = 0
    @State private var age = 0
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var match = "any"
    @State private var categories: [String] = BookCategory.all.map(\.value)
    @State private var showGrowth = true
    @State private var density: BookDensity = .balanced
    @State private var title = ""
    @State private var titleTouched = false
    @State private var isBusy = false
    @State private var error: String?
    @State private var didSeed = false

    private struct Candidate: Identifiable {
        let id: Int
        let name: String
        let birthday: String
    }

    private var today: String { Date().dayKey() }

    /// People of this household with a birthday that has arrived — the server refuses a book about anybody else.
    private var people: [Candidate] {
        let ownFamily = authService.currentUser?.familyId
        return allPeople.compactMap { person in
            guard let id = person.remoteId.flatMap(Int.init), let birthday = person.birthday, !person.isPregnancy else { return nil }
            if let ownFamily, (person.familyRemoteId ?? ownFamily) != ownFamily { return nil }
            let day = birthday.dayKey()
            guard day <= today else { return nil }
            return Candidate(id: id, name: person.name, birthday: day)
        }
    }

    private var chosen: [Candidate] {
        personIds.compactMap { id in people.first { $0.id == id } }
    }

    private var period: BookPlans.Period? {
        let first = chosen.first
        switch preset.value {
        case BookPreset.firstYear:
            return first.map { BookPlans.firstYear(birthday: $0.birthday) }
        case BookPreset.year:
            guard let first else { return nil }
            switch yearKind {
            case .past: return BookPlans.pastYear(today: today)
            case .age: return BookPlans.yearOfAge(birthday: first.birthday, age: age)
            case .calendar: return BookPlans.calendarYear(year)
            }
        case BookPreset.familyYear:
            return BookPlans.calendarYear(year)
        default:
            let start = customStart.dayKey()
            let last = customEnd.dayKey()
            guard last >= start else { return nil }
            return BookPlans.Period(start: start, end: BookDay.addDays(last, 1))
        }
    }

    private var shownTitle: String {
        guard !titleTouched, let period, !chosen.isEmpty else { return title }
        return BookPlans.defaultTitle(preset: preset.value, names: chosen.map(\.name), period: period, yearKind: yearKind, age: age)
    }

    private var notBornYet: [Candidate] {
        guard let period else { return [] }
        return chosen.filter { $0.birthday >= period.end }
    }

    private var years: [Int] {
        let thisYear = Int(today.prefix(4)) ?? 2026
        let earliest = people.compactMap { Int($0.birthday.prefix(4)) }.min() ?? thisYear
        return Array(stride(from: thisYear, through: min(earliest, thisYear), by: -1))
    }

    private var isReady: Bool {
        period != nil && !chosen.isEmpty && notBornYet.isEmpty && !categories.isEmpty && !isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.label).font(BookType.serif(.title3))
                            Text(preset.blurb).font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: preset.symbol)
                    }
                }

                peopleSection
                if preset.value != BookPreset.firstYear { whenSection }

                Section {
                    if let period {
                        Text("Covers \(BookDay.bookDates(start: period.start, end: period.end))")
                    } else {
                        Text("Choose who and when.").foregroundStyle(.secondary)
                    }
                    if !notBornYet.isEmpty {
                        Text("\(BookAssembler.joinNames(notBornYet.map(\.name))) \(notBornYet.count > 1 ? "were" : "was") not born yet.")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote)

                Section("What to include") {
                    ForEach(BookCategory.all) { category in
                        Toggle(category.label, isOn: Binding(
                            get: { categories.contains(category.value) },
                            set: { on in
                                categories = on ? categories + [category.value] : categories.filter { $0 != category.value }
                            }
                        ))
                    }
                    Toggle("Growth", isOn: $showGrowth)
                    Picker("How many photos", selection: $density) {
                        ForEach(BookDensity.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Title", text: Binding(
                        get: { shownTitle },
                        set: { title = String($0.prefix(120)); titleTouched = true }
                    ))
                    .font(BookType.serif(.title3))
                } header: {
                    Text("Title")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            Spacer()
                            if isBusy {
                                ProgressView()
                                Text("Gathering…")
                            } else {
                                Text("Make the Draft").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isReady)
                }
            }
            .navigationTitle("New Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isBusy)
            .onAppear(perform: seed)
        }
    }

    // MARK: - Sections

    private var peopleSection: some View {
        Section {
            if people.isEmpty {
                Text("Add someone with a birthday first.").foregroundStyle(.secondary)
            }
            ForEach(people) { person in
                Button {
                    toggle(person.id)
                } label: {
                    HStack {
                        Text(person.name).foregroundStyle(.primary)
                        Spacer()
                        if personIds.contains(person.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityAddTraits(personIds.contains(person.id) ? .isSelected : [])
            }
            if !preset.isSingle && chosen.count > 1 {
                Picker("Which photos", selection: $match) {
                    Text("Photos of any of them").tag("any")
                    Text("Only photos of all of them").tag("all")
                }
            }
        } header: {
            Text(preset.isSingle ? "Whose book?" : "Who's in it?")
        }
    }

    @ViewBuilder
    private var whenSection: some View {
        Section("When") {
            if preset.value == BookPreset.year {
                Picker("Which year", selection: $yearKind) {
                    ForEach(BookPlans.YearKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if preset.value == BookPreset.familyYear || (preset.value == BookPreset.year && yearKind == .calendar) {
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
            }
            if preset.value == BookPreset.year && yearKind == .age, let first = chosen.first {
                Picker("Age", selection: $age) {
                    ForEach(0...BookPlans.ageNow(birthday: first.birthday, today: today), id: \.self) { age in
                        Text(age == 0 ? "Birth to one" : "\(age) to \(age + 1)").tag(age)
                    }
                }
            }
            if preset.value == BookPreset.custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("Through", selection: $customEnd, displayedComponents: .date)
            }
        }
    }

    // MARK: - Behaviour

    /// The web's defaults: the youngest child for a book about one person; for a family year, last year (this one in December) and everybody born by its end.
    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        let thisYear = Int(today.prefix(4)) ?? 2026
        let familyYear = today.dropFirst(5).prefix(2) == "12" ? thisYear : thisYear - 1
        year = preset.value == BookPreset.familyYear ? familyYear : thisYear
        showGrowth = preset.value != BookPreset.familyYear
        if preset.value == BookPreset.familyYear {
            let yearEnd = String(format: "%04d-01-01", familyYear + 1)
            personIds = people.filter { $0.birthday < yearEnd }.map(\.id)
        } else if let youngest = people.max(by: { $0.birthday < $1.birthday }) {
            personIds = [youngest.id]
        }
    }

    private func toggle(_ id: Int) {
        error = nil
        if preset.isSingle {
            personIds = [id]
            age = 0
        } else if personIds.contains(id) {
            personIds.removeAll { $0 == id }
        } else {
            personIds.append(id)
        }
    }

    private func create() async {
        guard let period, isReady else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }

        let title = shownTitle
        let ids = chosen.map(\.id)
        let sentCategories = Set(categories).count == BookCategory.all.count ? [] : categories.sorted()
        do {
            let gathered = try await service.sources(personIds: ids, preset: preset.value, startDate: period.start, endDate: period.end)
            let plan = BookDTO(
                personIds: ids,
                preset: preset.value,
                title: title,
                startDate: period.start,
                endDate: period.end,
                density: density.rawValue,
                categories: sentCategories,
                match: match,
                showGrowth: showGrowth,
                items: []
            )
            let draft = BookAssembler.draft(plan, sources: gathered.sources, density: density)
            let created = try await service.createBook(
                personIds: ids,
                preset: preset.value,
                startDate: period.start,
                endDate: period.end,
                content: draft.content(reviewedAt: nil)
            )
            dismiss()
            onCreated(created)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

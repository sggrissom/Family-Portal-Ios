import SwiftUI
import SwiftData

/// What a `GetSameAge` row reads as — a port of the pure parts of the web's `SameAgeRows`.
enum SameAgeText {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "now" when the person is that age today, else the month they were — "Dec 2019".
    static func when(_ row: SameAgeRowDTO, ageMonths: Int, today: Date = Date().localRecordDay()) -> String {
        if AgeSteps.monthsOld(birthday: row.person.birthday, at: today) == ageMonths {
            return Copy.sameAge.now
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month], from: row.date)
        return "\(months[(parts.month ?? 1) - 1]) \(parts.year ?? 0)"
    }

    /// "3 ft 2 in · 32 lb", each read at the age it was actually taken.
    static func measurements(_ row: SameAgeRowDTO) -> String {
        [row.height, row.weight].compactMap { $0 }.map { record in
            MeasurementConversion.formatLikeWeb(
                record.value,
                unit: unitFromString(record.unit),
                ageMonths: Double(AgeSteps.monthsOld(birthday: row.person.birthday, at: record.measurementDate))
            )
        }
        .joined(separator: " · ")
    }

    /// Portraits read oldest first, as `portraitOrder` sorts them — the order a family photo wall would hang in.
    static func portraitOrder(_ rows: [SameAgeRowDTO]) -> [SameAgeRowDTO] {
        rows.sorted { a, b in
            a.person.birthday != b.person.birthday ? a.person.birthday < b.person.birthday : a.person.id < b.person.id
        }
    }

    /// "14 photos · 2 moments", or "Measured" when a measurement is all there is — a row on a profile's same-age highlight.
    static func summary(_ row: SameAgeRowDTO) -> String {
        var parts: [String] = []
        if !row.photoIds.isEmpty { parts.append(Copy.person.photoCount(row.photoIds.count)) }
        if !row.milestones.isEmpty { parts.append(Copy.person.momentCount(row.milestones.count)) }
        if parts.isEmpty && (row.height != nil || row.weight != nil) { parts.append(Copy.person.measuredThen) }
        return parts.joined(separator: " · ")
    }

    /// The age a record was actually taken at, which is rarely exactly the row's age.
    static func actualAge(_ row: SameAgeRowDTO, at date: Date) -> String {
        AgeSteps.ageTitle(AgeSteps.monthsOld(birthday: row.person.birthday, at: date))
    }
}

/// One row per person who has reached the age: when, measurements, the nearest photos and milestones, each with the age it actually happened. A person with nothing collapses to one line, or is left out with `hideEmpty` — the browse page counts them instead.
/// Links resolve server ids against the store and use destination links, so the rows work inside a record's sheet as well as on a tab.
struct SameAgeRows: View {
    let rows: [SameAgeRowDTO]
    let ageMonths: Int
    var photoLimit = 6
    var hideEmpty = false

    @Query private var people: [Person]

    var body: some View {
        // Names are told apart across everyone, before the empty rows go: two Alexes stay distinguishable when only one has records at this age.
        // Indexed once per draw: every row resolves its person against this.
        let peopleById = people.byServerId()
        let labels = FamilyGroups.chipLabels(rows.compactMap { peopleById[$0.person.id] })
        VStack(alignment: .leading, spacing: 14) {
            ForEach(hideEmpty ? rows.filter { !$0.isEmpty } : rows) { row in
                let person = peopleById[row.person.id]
                let name = person.flatMap { labels[$0.id] } ?? row.person.name
                if row.isEmpty {
                    HStack {
                        personLink(person, name: name)
                        Text(Copy.sameAge.noRecords)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            personLink(person, name: name)
                            Text(SameAgeText.when(row, ageMonths: ageMonths))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let measured = SameAgeText.measurements(row)
                            if !measured.isEmpty {
                                Text(measured)
                                    .font(.caption)
                            }
                        }
                        if !row.photoIds.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(row.photoIds.prefix(photoLimit), id: \.self) { photoId in
                                        photoThumb(photoId)
                                    }
                                }
                            }
                        }
                        let folded = Interviews.fold(row.milestones)
                        ForEach(folded.loose, id: \.id) { milestone in
                            milestoneLine(milestone, row: row)
                        }
                        ForEach(row.contextMilestones, id: \.id) { milestone in
                            contextLine(milestone)
                        }
                        ForEach(folded.groups) { answers in
                            InterviewCardView(model: InterviewCardModel(
                                answers: answers,
                                personName: nil,
                                birthday: row.person.birthday,
                                interview: row.interviews.first { $0.id == answers.interviewId }
                            ))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func personLink(_ person: Person?, name: String) -> some View {
        if let person {
            NavigationLink {
                PersonDetailView(personId: person.id, allowsManagementActions: false)
            } label: {
                Text(name).font(.subheadline.weight(.semibold))
            }
        } else {
            Text(name).font(.subheadline.weight(.semibold))
        }
    }

    private func photoThumb(_ remoteId: Int) -> some View {
        // The server can return a photo before it reaches the local mirror.
        NavigationLink {
            RemotePhotoDetailView(remoteId: remoteId)
        } label: {
            RemotePhotoView(remoteId: remoteId, size: .thumb)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityLabel("View photo")
    }

    private func milestoneLine(_ milestone: MilestoneDTO, row: SameAgeRowDTO) -> some View {
        let category = MilestoneCategory(rawValue: milestone.category) ?? .other
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: category.icon)
                .foregroundStyle(category.color)
            Text(milestone.displayText)
                .lineLimit(2)
            Text(Copy.milestoneDetail.atAge(SameAgeText.actualAge(row, at: milestone.milestoneDate)))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func contextLine(_ milestone: MilestoneDTO) -> some View {
        let category = MilestoneCategory(rawValue: milestone.category) ?? .other
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: category.icon)
                .foregroundStyle(category.color)
            Text(milestone.displayText)
                .lineLimit(2)
            Text(milestone.recordTime?.label ?? "")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

/// "At 3 years 4 months" and everybody else at that age, under a record — with **See everything at this age →**.
/// Anchored on a person by server id; somebody still uploading has none, and the strip stays away.
struct SameAgeStrip: View {
    let anchorRemoteId: Int
    let ageMonths: Int

    @Environment(NetworkMonitor.self) private var network
    @State private var loader = SameAgeLoader()

    var body: some View {
        // A container, not a `Group`: a `Group` hands its modifiers to its children, and before the answer arrives there are none, so the `.task` that fetches it would never run.
        VStack(alignment: .leading, spacing: 0) {
            if let response = loader.response {
                let others = response.rows.filter { $0.person.id != anchorRemoteId && !$0.isEmpty }
                ContextSection(Copy.sameAge.atThisAge(AgeSteps.ageTitle(response.ageMonths)), kind: .sameAge) {
                    NavigationLink {
                        SameAgeView(ageMonths: response.ageMonths, fromRemoteId: response.fromPersonId, view: .details)
                    } label: {
                        Text(Copy.sameAge.seeAll)
                            .font(.subheadline)
                    }
                } content: {
                    if others.isEmpty {
                        Text(Copy.sameAge.nobodyElse)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        SameAgeRows(rows: others, ageMonths: response.ageMonths, photoLimit: 4)
                    }
                }
            }
        }
        .task(id: "\(anchorRemoteId)-\(ageMonths)") {
            await loader.load(ageMonths: ageMonths, fromPersonId: anchorRemoteId, isConnected: network.isConnected)
        }
    }
}

/// A strip for one person on one day — how old they were then — or nothing when the person has no server id or birthday yet.
struct PersonSameAgeStrip: View {
    let person: Person?
    let date: Date

    var body: some View {
        if let person,
           !person.isPregnancy,
           let remoteId = person.serverId,
           let birthday = person.birthday {
            let months = AgeSteps.monthsOld(birthday: birthday, at: date)
            if months >= 0 {
                SameAgeStrip(anchorRemoteId: remoteId, ageMonths: months)
            }
        }
    }
}

/// Compare at the age of a tagged person. A person page or the only eligible person can supply the initial selection.
struct PhotoSameAgeSection: View {
    let photo: Photo
    let openedFrom: UUID?

    @State private var anchorId: UUID?

    var body: some View {
        let people = photo.taggedPeople
            .filter { person in
                guard !person.isPregnancy, person.serverId != nil, let birthday = person.birthday else { return false }
                return AgeSteps.monthsOld(birthday: birthday, at: photo.photoDate) >= 0
            }
            .sorted { FamilyGroups.isOlder($1, $0) }
        let ids = people.map(\.id)

        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if people.count > 1 {
                    let labels = FamilyGroups.chipLabels(people)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Compare at the same age")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Picker("Compare at the same age", selection: $anchorId) {
                            Text("Choose a person").tag(nil as UUID?)
                            ForEach(people) { person in
                                Text(labels[person.id] ?? person.name).tag(Optional(person.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                PersonSameAgeStrip(person: people.first { $0.id == anchorId }, date: photo.photoDate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: ids, initial: true) { _, ids in
                if let anchorId, ids.contains(anchorId) { return }
                anchorId = SameAgeAnchor.initial(tagged: ids, openedFrom: openedFrom)
            }
        }
    }
}

/// Which person a photo's Same age strip starts on.
enum SameAgeAnchor {
    /// The person the photo was opened from, when they are in it; else the only person in it; else nobody, for the chips to decide.
    static func initial(tagged: [UUID], openedFrom: UUID?) -> UUID? {
        if let openedFrom, tagged.contains(openedFrom) { return openedFrom }
        return tagged.count == 1 ? tagged.first : nil
    }
}

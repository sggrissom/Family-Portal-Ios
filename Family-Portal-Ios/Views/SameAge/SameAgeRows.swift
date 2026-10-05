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

    /// The age a record was actually taken at, which is rarely exactly the row's age.
    static func actualAge(_ row: SameAgeRowDTO, at date: Date) -> String {
        AgeSteps.ageTitle(AgeSteps.monthsOld(birthday: row.person.birthday, at: date))
    }
}

/// One row per person who has reached the age: when, measurements, the nearest photos and milestones, each with the age it actually happened. A person with nothing collapses to one line.
/// Links resolve server ids against the store and use destination links, so the rows work inside a record's sheet as well as on a tab.
struct SameAgeRows: View {
    let rows: [SameAgeRowDTO]
    let ageMonths: Int
    var photoLimit = 6

    @Query private var people: [Person]
    @Query private var photos: [Photo]
    @Query private var milestones: [Milestone]

    var body: some View {
        let labels = FamilyGroups.chipLabels(rows.compactMap { localPerson($0.person.id) })
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows) { row in
                let name = localPerson(row.person.id).flatMap { labels[$0.id] } ?? row.person.name
                if row.isEmpty {
                    HStack {
                        personLink(row, name: name)
                        Text(Copy.sameAge.noRecords)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            personLink(row, name: name)
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
                        ForEach(row.milestones, id: \.id) { milestone in
                            milestoneLine(milestone, row: row)
                        }
                    }
                }
            }
        }
    }

    private func localPerson(_ remoteId: Int) -> Person? {
        people.first { $0.remoteId == String(remoteId) }
    }

    @ViewBuilder
    private func personLink(_ row: SameAgeRowDTO, name: String) -> some View {
        if let person = localPerson(row.person.id) {
            NavigationLink {
                PersonDetailView(personId: person.id, allowsManagementActions: false)
            } label: {
                Text(name).font(.subheadline.weight(.semibold))
            }
        } else {
            Text(name).font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private func photoThumb(_ remoteId: Int) -> some View {
        let thumb = RemotePhotoView(remoteId: remoteId, size: .thumb)
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        if let photo = photos.first(where: { $0.remoteId == String(remoteId) }) {
            NavigationLink {
                PhotoDetailView(photoId: photo.id)
            } label: {
                thumb
            }
            .accessibilityLabel("View photo")
        } else {
            thumb
        }
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
}

/// "At 3 years 4 months" and everybody else at that age, under a record — with **See everything at this age →**.
/// Anchored on a person by server id; somebody still uploading has none, and the strip stays away.
struct SameAgeStrip: View {
    let anchorRemoteId: Int
    let ageMonths: Int
    /// Hidden when nobody else has anything, instead of saying so — Story's overview does this.
    var hideWhenEmpty = false

    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @State private var loader = SameAgeLoader()

    var body: some View {
        // A container, not a `Group`: a `Group` hands its modifiers to its children, and before the answer arrives there are none, so the `.task` that fetches it would never run.
        VStack(alignment: .leading, spacing: 0) {
            if let response = loader.response {
                let others = response.rows.filter { $0.person.id != anchorRemoteId && !$0.isEmpty }
                if !(hideWhenEmpty && others.isEmpty) {
                    ContextSection(Copy.sameAge.atThisAge(AgeSteps.ageTitle(response.ageMonths)), kind: .sameAge) {
                        NavigationLink {
                            SameAgeView(ageMonths: response.ageMonths, fromRemoteId: response.fromPersonId)
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
        }
        .task(id: "\(anchorRemoteId)-\(ageMonths)") {
            await loader.load(ageMonths: ageMonths, fromPersonId: anchorRemoteId, isConnected: network?.isConnected ?? true)
        }
    }
}

/// A strip for one person on one day — how old they were then — or nothing when the person has no server id or birthday yet.
struct PersonSameAgeStrip: View {
    let person: Person?
    let date: Date
    var hideWhenEmpty = false

    var body: some View {
        if let person,
           !person.isPregnancy,
           let remoteId = person.remoteId.flatMap(Int.init),
           let birthday = person.birthday {
            let months = AgeSteps.monthsOld(birthday: birthday, at: date)
            if months >= 0 {
                SameAgeStrip(anchorRemoteId: remoteId, ageMonths: months, hideWhenEmpty: hideWhenEmpty)
            }
        }
    }
}

/// A photo's strip. The anchor is the person it was opened from; for a group photo opened from Photos, a chip row of the people in it chooses — nobody is picked invisibly. A photo of one person anchors on them, shown as the one chip.
struct PhotoSameAgeSection: View {
    let photo: Photo
    let openedFrom: UUID?

    @State private var anchorId: UUID?
    @State private var didSeed = false

    private var tagged: [Person] {
        photo.taggedPeople.sorted { FamilyGroups.isOlder($1, $0) }
    }

    var body: some View {
        let people = tagged
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if people.count > 1 || openedFrom == nil {
                    PersonChips(selection: $anchorId, only: Set(people.map(\.id)))
                }
                PersonSameAgeStrip(person: people.first { $0.id == anchorId }, date: photo.photoDate)
            }
            .onAppear {
                guard !didSeed else { return }
                didSeed = true
                anchorId = SameAgeAnchor.initial(tagged: people.map(\.id), openedFrom: openedFrom)
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

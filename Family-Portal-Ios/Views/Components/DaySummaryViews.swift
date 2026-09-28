import SwiftUI
import SwiftData

/// One day's records as History, Story and Home show them: birthday dividers, milestones as whole cards, one checkup row per person, one card per event with the family's results, and the rest of the photos as a mosaic that opens the set.
struct DaySummaryView: View {
    let day: DaySummary
    /// `YYYY-MM-DD` of the device's today, for "Today" and "Yesterday".
    let today: String
    let people: [UUID: Person]
    /// The person a Story is about: their own name is left off rows that could only be theirs.
    var subjectId: UUID?
    /// Opens a checkup's measurement. Owned by the list, so there is one sheet rather than one per row.
    let onOpenMeasurement: (GrowthData) -> Void

    @Query private var allPeople: [Person]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DaySummaries.dayLabel(day.day, today: today))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(day.birthdays, id: \.personId) { birthday in
                if let person = people[birthday.personId] {
                    birthdayDivider(Copy.home.turned(name: firstName(person), age: birthday.age))
                }
            }

            ForEach(day.milestones) { milestone in
                VStack(alignment: .leading, spacing: 2) {
                    if subjectId == nil, let person = milestone.person {
                        Text(person.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    MilestoneRowView(milestone: milestone)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            ForEach(day.events) { event in
                eventCard(event)
            }

            ForEach(day.checkups) { checkup in
                checkupRow(checkup)
            }

            if let photos = day.photos {
                photoMosaic(photos)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func firstName(_ person: Person) -> String {
        person.name.split(separator: " ").first.map(String.init) ?? person.name
    }

    private func birthdayDivider(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text("🎂 \(text)")
                .font(.subheadline)
                .fixedSize()
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
        .padding(.vertical, 4)
    }

    private func checkupRow(_ checkup: DayCheckup) -> some View {
        let person = people[checkup.personId]
        let values = [checkup.height, checkup.weight].compactMap { $0 }.map { MeasurementConversion.format($0) }
        let who = (subjectId == checkup.personId ? nil : person.map(firstName))
        let lead = who.map { "\($0) \(Copy.home.checkup)" } ?? Copy.home.checkupTitle
        let extra = checkup.extra > 0 ? " (+\(checkup.extra))" : ""
        return Button {
            if let record = checkup.height ?? checkup.weight {
                onOpenMeasurement(record)
            }
        } label: {
            HStack {
                Image(systemName: MeasurementType.height.icon)
                    .foregroundStyle(MeasurementType.height.color)
                Text("\(lead) · \(values.joined(separator: " · "))\(extra)")
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func eventCard(_ event: DayEvent) -> some View {
        let activityPeople = ActivityPeople(allPeople)
        return VStack(alignment: .leading, spacing: 6) {
            Label(event.event.name, systemImage: "trophy")
                .font(.subheadline.weight(.semibold))
            ForEach(event.appearances) { appearance in
                VStack(alignment: .leading, spacing: 2) {
                    Text(appearance.detail.entry.name)
                        .font(.caption.weight(.semibold))
                    ForEach(appearance.detail.results) { result in
                        ActivityResultRow(result: result, people: activityPeople)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func photoMosaic(_ group: DayPhotoGroup) -> some View {
        let names = group.personIds.compactMap { people[$0] }.map(firstName)
        let caption = ([Copy.home.photoCount(group.count)] + (names.isEmpty ? [] : [names.joined(separator: ", ")]))
            .joined(separator: " · ")
        return NavigationLink(value: AppRoute.photoSet(ids: group.allIds, title: DaySummaries.dayLabel(day.day, today: today))) {
            VStack(alignment: .leading, spacing: 4) {
                MosaicThumbnails(photoIds: group.mosaicIds)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Up to four thumbnails in a row, read from the store so photos still uploading show too.
struct MosaicThumbnails: View {
    let photoIds: [UUID]

    @Query private var photos: [Photo]

    init(photoIds: [UUID]) {
        self.photoIds = photoIds
        let ids = photoIds
        _photos = Query(filter: #Predicate<Photo> { ids.contains($0.id) })
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(photoIds, id: \.self) { id in
                if let photo = photos.first(where: { $0.id == id }) {
                    PhotoThumbnailView(imageData: photo.imageData, title: "", remoteId: photo.remoteId)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

/// A list of days — one sheet for all their measurements, so rows never each carry one.
struct DaySummaryList: View {
    let days: [DaySummary]
    let today: String
    var subjectId: UUID?

    @Query private var people: [Person]
    @State private var openMeasurement: GrowthData?

    var body: some View {
        let byId = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(days) { day in
                DaySummaryView(day: day, today: today, people: byId, subjectId: subjectId) { openMeasurement = $0 }
            }
        }
        .sheet(item: $openMeasurement) { MeasurementDetailSheetView(measurement: $0) }
    }
}

/// A set of photos opened from a day's mosaic.
struct PhotoSetView: View {
    let ids: [UUID]
    let title: String

    @Query private var photos: [Photo]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    init(ids: [UUID], title: String) {
        self.ids = ids
        self.title = title
        let wanted = ids
        _photos = Query(filter: #Predicate<Photo> { wanted.contains($0.id) }, sort: \Photo.photoDate, order: .reverse)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    NavigationLink(value: PhotoRoute(id: photo.id)) {
                        PhotoThumbnailView(imageData: photo.imageData, title: photo.title, remoteId: photo.remoteId)
                    }
                }
            }
            .padding(4)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

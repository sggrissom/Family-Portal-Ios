import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Query private var people: [Person]

    @State private var showEditSheet = false
    let allowsManagementActions: Bool

    private var person: Person? { people.first }

    init(personId: UUID, allowsManagementActions: Bool = true) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
        self.allowsManagementActions = allowsManagementActions
    }

    private var age: String? {
        guard let person, let birthday = person.birthday else { return nil }
        return AgeCalculator.age(from: birthday, isPregnancy: person.isPregnancy)
    }

    private var latestHeight: GrowthData? {
        person?.growthData
            .filter { $0.measurementType == .height }
            .sorted { $0.date > $1.date }
            .first
    }

    private var latestWeight: GrowthData? {
        person?.growthData
            .filter { $0.measurementType == .weight }
            .sorted { $0.date > $1.date }
            .first
    }

    private var recentMilestones: [Milestone] {
        (person?.milestones ?? [])
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { $0 }
    }

    private var recentPhotos: [Photo] {
        (person?.photos ?? [])
            .sorted { $0.photoDate > $1.photoDate }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        if let person {
            ScrollView {
                VStack(spacing: 24) {
                    PersonAvatarView(person: person, size: 100)
                        .padding(.top, 20)

                    Text(person.name)
                        .font(.title)
                        .fontWeight(.bold)

                    GroupBox("Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let relationship = person.relationship {
                                detailRow(label: "Relationship", value: relationship.capitalized)
                            }
                            detailRow(label: "Gender", value: person.gender.rawValue.capitalized)

                            if let birthday = person.birthday {
                                detailRow(label: "Birthday", value: birthday.formatted(date: .long, time: .omitted))
                            }

                            if let age {
                                detailRow(label: "Age", value: age)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)

                    GroupBox("Latest Measurements") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let height = latestHeight {
                                measurementRow(
                                    icon: "ruler",
                                    label: "Height",
                                    value: formatMeasurement(height)
                                )
                            }

                            if let weight = latestWeight {
                                measurementRow(
                                    icon: "scalemass",
                                    label: "Weight",
                                    value: formatMeasurement(weight)
                                )
                            }

                            if latestHeight == nil && latestWeight == nil {
                                Text("No measurements yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }

                            NavigationLink(destination: MeasurementListView(personId: person.id)) {
                                HStack {
                                    Text("See All Measurements")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .accessibilityHidden(true)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)

                    // Only when the person has a remote id: `GetPersonSeason` is addressed by server id, and a person created offline has no server record yet.
                    if let personRemoteId = person.remoteId.flatMap(Int.init) {
                        GroupBox("Activities") {
                            NavigationLink(
                                destination: PersonSeasonView(personId: personRemoteId, personName: person.name)
                            ) {
                                HStack {
                                    Label("This Season", systemImage: "trophy")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .accessibilityHidden(true)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .padding(.horizontal)
                    }

                    GroupBox("Recent Milestones") {
                        VStack(alignment: .leading, spacing: 8) {
                            if recentMilestones.isEmpty {
                                Text("No milestones yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(recentMilestones) { milestone in
                                    MilestoneRowView(milestone: milestone)
                                }
                            }

                            NavigationLink(destination: MilestoneListView(personId: person.id)) {
                                HStack {
                                    Text("See All Milestones")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .accessibilityHidden(true)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)

                    GroupBox("Photos") {
                        VStack(alignment: .leading, spacing: 8) {
                            if recentPhotos.isEmpty {
                                Text("No photos yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(recentPhotos) { photo in
                                        NavigationLink(value: PhotoRoute(id: photo.id)) {
                                            PhotoThumbnailView(imageData: photo.imageData, title: photo.title, remoteId: photo.remoteId)
                                        }
                                    }
                                }
                            }

                            NavigationLink(destination: PersonPhotosView(person: person)) {
                                HStack {
                                    Text("See All Photos")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .accessibilityHidden(true)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)

                            if allowsManagementActions && !recentPhotos.isEmpty {
                                NavigationLink(destination: ProfilePhotoPickerView(person: person)) {
                                    HStack {
                                        Text("Choose Profile Photo")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .accessibilityHidden(true)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PhotoRoute.self) { route in
                PhotoDetailView(photoId: route.id)
            }
            .toolbar {
                if allowsManagementActions {
                    // No delete affordance: the backend has no DeletePerson proc, so a local delete is undone by the next pull.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit \(person.name)")
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPersonView(person: person)
            }
        } else {
            ContentUnavailableView("Person Not Found", systemImage: "person.slash")
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func measurementRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func formatMeasurement(_ data: GrowthData) -> String {
        let valueStr = data.value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", data.value)
            : String(format: "%.1f", data.value)
        let dateStr = data.date.formatted(date: .abbreviated, time: .omitted)
        return "\(valueStr) \(data.unit.rawValue) (\(dateStr))"
    }
}

// MARK: - Person Photos View

struct PersonPhotosView: View {
    let person: Person

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    /// SwiftData does not order to-many relationships, so `person.photos` comes out arbitrary.
    private var photos: [Photo] {
        person.photos.sorted { $0.photoDate > $1.photoDate }
    }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle",
                    description: Text("No photos tagged with \(person.name).")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(photos) { photo in
                            NavigationLink(destination: PhotoDetailView(photoId: photo.id)) {
                                PhotoThumbnailView(imageData: photo.imageData, title: photo.title, remoteId: photo.remoteId)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .navigationTitle("\(person.name)'s Photos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

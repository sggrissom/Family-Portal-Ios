import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var people: [Person]

    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false

    private var person: Person? { people.first }

    init(personId: UUID) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
    }

    private var age: String? {
        guard let birthday = person?.birthday else { return nil }
        return AgeCalculator.age(from: birthday)
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
        Array((person?.photos ?? []).prefix(4))
    }

    var body: some View {
        if let person {
            ScrollView {
                VStack(spacing: 24) {
                    PersonAvatarView(
                        name: person.name,
                        type: person.type,
                        profilePhotoRemoteId: person.profilePhotoId,
                        size: 100
                    )
                        .padding(.top, 20)

                    Text(person.name)
                        .font(.title)
                        .fontWeight(.bold)

                    GroupBox("Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            detailRow(label: "Type", value: person.type.rawValue.capitalized)
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

                    // Latest Measurements Section
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

                    // Recent Milestones Section
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

                    // Photos Section
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
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PhotoRoute.self) { route in
                PhotoDetailView(photoId: route.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPersonView(person: person)
            }
            .confirmationDialog(
                "Delete \(person.name)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(person)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \(person.name)? This will also delete all their measurements and milestones.")
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

    var body: some View {
        Group {
            if person.photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle",
                    description: Text("No photos tagged with \(person.name).")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(person.photos) { photo in
                            NavigationLink(value: PhotoRoute(id: photo.id)) {
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
        .navigationDestination(for: PhotoRoute.self) { route in
            PhotoDetailView(photoId: route.id)
        }
    }
}

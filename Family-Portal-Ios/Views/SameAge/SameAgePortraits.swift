import SwiftUI
import SwiftData

/// **Portraits** — one face per person at the age, oldest first, each with how old they actually were in it. A port of the web's `SameAgePortraits`.
/// One face still shows (with a line saying so), the people without a photo fold away under a count, and none at all says so. Tapping a face opens the whole photo, where **Another photo** cycles that person's picks — kept in view state only, so key the view on the age to start each age from the best.
struct SameAgePortraits: View {
    let rows: [SameAgeRowDTO]
    let ageMonths: Int

    @Query private var people: [Person]
    /// Server person id → index into that row's portraits.
    @State private var picks: [Int: Int] = [:]
    @State private var open: OpenPortrait?

    private static let tileSize: CGFloat = 140

    private struct OpenPortrait: Identifiable {
        let id: Int
    }

    var body: some View {
        let ordered = SameAgeText.portraitOrder(rows)
        let labels = FamilyGroups.chipLabels(ordered.compactMap { localPerson($0.person.id) })
        let name = { (row: SameAgeRowDTO) in localPerson(row.person.id).flatMap { labels[$0.id] } ?? row.person.name }
        let pictured = ordered.filter { !$0.portraits.isEmpty }
        let missing = ordered.filter { $0.portraits.isEmpty }
        let age = AgeSteps.ageTitle(ageMonths)

        VStack(alignment: .leading, spacing: 12) {
            if pictured.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.sameAge.noPortraits(age))
                    Text(Copy.sameAge.tryAnotherAge)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize), spacing: 12, alignment: .top)], spacing: 16) {
                    ForEach(pictured) { row in
                        tile(row, name: name(row))
                    }
                }
            }
            if pictured.count == 1, let only = pictured.first {
                Text(Copy.sameAge.onlyPictured(name(only)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !pictured.isEmpty && !missing.isEmpty {
                DisclosureGroup {
                    Text(missing.map(name).joined(separator: ", "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(Copy.sameAge.missingPhotos(age, missing.count))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.sameAge.portraits)
        .sheet(item: $open) { open in
            if let row = pictured.first(where: { $0.person.id == open.id }) {
                SameAgePortraitViewer(row: row, name: name(row), pick: pickBinding(row))
            }
        }
    }

    private func localPerson(_ remoteId: Int) -> Person? {
        people.first { $0.remoteId == String(remoteId) }
    }

    private func pick(_ row: SameAgeRowDTO) -> Int {
        min(picks[row.person.id] ?? 0, row.portraits.count - 1)
    }

    private func pickBinding(_ row: SameAgeRowDTO) -> Binding<Int> {
        Binding(get: { pick(row) }, set: { picks[row.person.id] = $0 })
    }

    private func tile(_ row: SameAgeRowDTO, name: String) -> some View {
        let portrait = row.portraits[pick(row)]
        let age = AgeSteps.photoAge(birthday: row.person.birthday, at: portrait.date)
        return Button {
            open = OpenPortrait(id: row.person.id)
        } label: {
            VStack(spacing: 4) {
                FaceCropView(photoId: portrait.photoId, box: portrait.box, size: Self.tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .id(portrait.photoId)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if !age.isEmpty {
                    Text(age)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.sameAge.openPortrait(name, age))
        .accessibilityAddTraits(.isButton)
    }
}

/// One person's portrait at the age, whole: the photo, the day and the age it was taken, **Another photo** through their picks, and the photo's own page.
private struct SameAgePortraitViewer: View {
    let row: SameAgeRowDTO
    let name: String
    @Binding var pick: Int

    @Environment(\.dismiss) private var dismiss
    @Query private var photos: [Photo]

    var body: some View {
        let portrait = row.portraits[pick]
        let count = row.portraits.count
        let age = AgeSteps.photoAge(birthday: row.person.birthday, at: portrait.date)

        NavigationStack {
            VStack(spacing: 16) {
                ZoomableView {
                    RemotePhotoView(remoteId: portrait.photoId, size: .large, contentMode: .fit)
                        .accessibilityLabel(Copy.sameAge.photoOf(name))
                }
                .id(portrait.photoId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 2) {
                    if !age.isEmpty {
                        Text(age)
                            .font(.headline)
                    }
                    Text(portrait.date.displayDay().formatted(date: .long, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    if count > 1 {
                        Button {
                            pick = (pick + 1) % count
                        } label: {
                            Text("\(Copy.sameAge.anotherPhoto) · \(Copy.sameAge.photoCount(pick + 1, count))")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let photo = photos.first(where: { $0.remoteId == String(portrait.photoId) }) {
                        NavigationLink(Copy.sameAge.openPhotoPage) {
                            PhotoDetailView(photoId: photo.id)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.sameAge.close) { dismiss() }
                }
            }
        }
    }
}

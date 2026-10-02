import SwiftUI
import SwiftData

/// **Side by side** — one face per person at the age, each with the age and day it was actually taken, and the people without a photo named as a gap rather than left out. One face is not a comparison, so it needs two. A port of the web's `SameAgeMontage`.
/// **Another photo** cycles a person's picks, kept in view state only, so key the view on the age to start each age from the best.
struct SameAgeMontage: View {
    let rows: [SameAgeRowDTO]

    @Query private var people: [Person]
    @Query private var photos: [Photo]
    /// Server person id → index into that row's portraits.
    @State private var picks: [Int: Int] = [:]

    private static let tileSize: CGFloat = 112

    var body: some View {
        let pictured = rows.filter { !$0.portraits.isEmpty }
        if pictured.count >= 2 {
            let labels = FamilyGroups.chipLabels(rows.compactMap { localPerson($0.person.id) })
            let name = { (row: SameAgeRowDTO) in localPerson(row.person.id).flatMap { labels[$0.id] } ?? row.person.name }
            let missing = rows.filter { $0.portraits.isEmpty }

            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(pictured) { row in
                        tile(row, name: name(row))
                    }
                }
                if !missing.isEmpty {
                    Text(Copy.sameAge.noPhoto(missing.map(name).joined(separator: ", ")))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Copy.sameAge.sideBySide)
        }
    }

    private func localPerson(_ remoteId: Int) -> Person? {
        people.first { $0.remoteId == String(remoteId) }
    }

    private func tile(_ row: SameAgeRowDTO, name: String) -> some View {
        let pick = min(picks[row.person.id] ?? 0, row.portraits.count - 1)
        let portrait = row.portraits[pick]
        let age = AgeSteps.photoAge(birthday: row.person.birthday, at: portrait.date)
        return VStack(spacing: 4) {
            face(portrait)
            VStack(spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                if !age.isEmpty {
                    Text(age)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(portrait.date.localDay().formatted(date: .long, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            if row.portraits.count > 1 {
                Button(Copy.sameAge.anotherPhoto) {
                    picks[row.person.id] = (pick + 1) % row.portraits.count
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func face(_ portrait: PortraitPhotoDTO) -> some View {
        let crop = FaceCropView(photoId: portrait.photoId, box: portrait.box, size: Self.tileSize)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .id(portrait.photoId)
        if let photo = photos.first(where: { $0.remoteId == String(portrait.photoId) }) {
            NavigationLink {
                PhotoDetailView(photoId: photo.id)
            } label: {
                crop
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.sameAge.viewPhoto)
        } else {
            crop
        }
    }
}

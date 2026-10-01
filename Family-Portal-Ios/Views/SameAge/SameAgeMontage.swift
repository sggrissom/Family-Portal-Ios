import SwiftUI
import SwiftData

/// Who the montage shows — a port of the web's `SameAgeMontage` choices.
enum SameAgeMontageRows {
    /// The people with a portrait near the age, in row order.
    static func pictured(_ rows: [SameAgeRowDTO]) -> [SameAgeRowDTO] {
        rows.filter { !$0.portraits.isEmpty }
    }

    /// The people without one, listed as a gap rather than left out.
    static func missing(_ rows: [SameAgeRowDTO]) -> [SameAgeRowDTO] {
        rows.filter { $0.portraits.isEmpty }
    }

    /// One face is not a comparison, so the montage needs two.
    static func shows(_ rows: [SameAgeRowDTO]) -> Bool {
        pictured(rows).count >= 2
    }

    /// The pick after `current`, wrapping round to the best.
    static func nextPick(_ current: Int, count: Int) -> Int {
        count > 0 ? (current + 1) % count : 0
    }
}

/// **Side by side** — one face per person at the age, each with the age and day it was actually taken. **Another photo** cycles a person's picks, kept in view state only, so key the view on the age to start each age from the best.
struct SameAgeMontage: View {
    let rows: [SameAgeRowDTO]

    @Query private var people: [Person]
    @Query private var photos: [Photo]
    /// Server person id → index into that row's portraits.
    @State private var picks: [Int: Int] = [:]

    private static let tileSize: CGFloat = 112

    var body: some View {
        if SameAgeMontageRows.shows(rows) {
            let labels = FamilyGroups.chipLabels(rows.compactMap { localPerson($0.person.id) })
            let name = { (row: SameAgeRowDTO) in localPerson(row.person.id).flatMap { labels[$0.id] } ?? row.person.name }
            let missing = SameAgeMontageRows.missing(rows)

            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(SameAgeMontageRows.pictured(rows)) { row in
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
                    picks[row.person.id] = SameAgeMontageRows.nextPick(pick, count: row.portraits.count)
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

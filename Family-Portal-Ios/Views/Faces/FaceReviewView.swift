import SwiftData
import SwiftUI

/// Telling the app who's who — the web's Faces page. Unnamed faces come grouped by likeness, each group with the server's guess when it has one; then the automatic tags, least certain first.
/// Online only (see `FaceReviewService`). Naming a face can auto-tag others, so each change reloads the review rather than editing it in place. Leaving after a change pulls family data, so photos pick up the people the server just put on them.
struct FaceReviewView: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var review: GetFaceReviewResponseDTO?
    /// Faces left out of their group before it is named. Cleared on every reload, since the groups are re-clustered.
    @State private var excluded: Set<Int> = []
    @State private var shownGroups = Self.groupsPerPage
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var didChange = false
    /// Server photo id → local id, so an automatic tag's face can open its photo.
    @State private var localPhotoIds: [Int: UUID] = [:]

    private static let groupsPerPage = 20

    private let service = FaceReviewService()

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            if let notice {
                Section {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.callout)
                }
            }

            if let review {
                content(review)
            } else if errorMessage == nil {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Faces")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onDisappear {
            guard didChange else { return }
            didChange = false
            Task { await syncService.pullFamilyData() }
        }
    }

    @ViewBuilder
    private func content(_ review: GetFaceReviewResponseDTO) -> some View {
        if review.unknownCount == 0 && review.autoCount == 0 {
            Section {
                Text(
                    review.enabled
                        ? "No faces are waiting for review. New photos are scanned for faces after they upload."
                        : "Face recognition isn't running on this server, so there's nothing to review."
                )
                .foregroundStyle(.secondary)
            }
        }

        if !review.groups.isEmpty {
            Section {
                ForEach(review.groups.prefix(shownGroups)) { group in
                    FaceGroupRow(
                        group: group,
                        people: review.people(inFamily: group.familyId),
                        familyName: review.families.count > 1 ? review.familyName(group.familyId) : nil,
                        excluded: $excluded,
                        isBusy: isBusy,
                        assign: { ids, personId in Task { await assign(ids, to: personId) } },
                        dismiss: { ids in Task { await dismiss(ids) } }
                    )
                }
                if review.groups.count > shownGroups {
                    Button("Show more (\(review.groups.count - shownGroups) more groups)") {
                        shownGroups += Self.groupsPerPage
                    }
                }
            } header: {
                Text("Who is this? (\(review.unknownCount))")
            } footer: {
                Text("Faces that look alike are grouped together. Tap a face to leave it out before you name the group. Someone missing from the list? Add them first, then come back.")
            }
        }

        if !review.autoTagged.isEmpty {
            Section {
                ForEach(review.autoTagged) { face in
                    autoTagRow(face, name: review.personName(face.personId))
                }
            } header: {
                Text("Check automatic tags (\(review.autoCount))")
            } footer: {
                Text("These were tagged automatically, least certain first. Confirming a match teaches the app what that person looks like.")
            }
        }
    }

    private func autoTagRow(_ face: PhotoFaceDTO, name: String) -> some View {
        HStack(spacing: 12) {
            Button {
                if let localId = localPhotoIds[face.photoId] {
                    navigator.push(PhotoRoute(id: localId))
                }
            } label: {
                FaceCropView(photoId: face.photoId, box: face.box, size: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(localPhotoIds[face.photoId] == nil)
            .accessibilityLabel("Open photo")

            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Button {
                        Task { await assign([face.id], to: face.personId) }
                    } label: {
                        Label("Confirm", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Confirm \(name)")

                    Button {
                        Task { await reject(face) }
                    } label: {
                        Label("Not them", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Not \(name)")
                }
                .controlSize(.small)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func load() async {
        if localPhotoIds.isEmpty {
            localPhotoIds = photoIndex()
        }
        do {
            let fresh = try await service.review()
            apply(fresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ fresh: GetFaceReviewResponseDTO) {
        review = fresh
        excluded = []
        navigator.updateFaceReviewCount(enabled: fresh.enabled, unknownCount: fresh.unknownCount, autoCount: fresh.autoCount)
    }

    /// Runs one change, then reloads. The notice is only shown once the reload has landed, so it never describes a list that is still stale.
    private func perform(_ change: () async throws -> String?) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        notice = nil
        defer { isBusy = false }

        do {
            let message = try await change()
            didChange = true
            let fresh = try await service.review()
            apply(fresh)
            notice = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assign(_ faceIds: [Int], to personId: Int) async {
        guard !faceIds.isEmpty else { return }
        await perform {
            let response = try await service.assign(faceIds: faceIds, to: personId)
            let name = review?.personName(personId) ?? "them"
            let more = response.autoTagged > 0 ? " and found \(name) in \(Self.photos(response.autoTagged)) more" : ""
            return "Tagged \(name) in \(Self.photos(response.assigned))\(more)."
        }
    }

    private func dismiss(_ faceIds: [Int]) async {
        guard !faceIds.isEmpty else { return }
        await perform {
            try await service.dismiss(faceIds: faceIds)
            return nil
        }
    }

    private func reject(_ face: PhotoFaceDTO) async {
        await perform {
            try await service.reject(faceIds: [face.id])
            return "Removed the tag. The face is back in “Who is this?”."
        }
    }

    private static func photos(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }

    private func photoIndex() -> [Int: UUID] {
        let photos = (try? modelContext.fetch(FetchDescriptor<Photo>())) ?? []
        return Dictionary(
            photos.compactMap { photo in photo.serverId.map { ($0, photo.id) } },
            uniquingKeysWith: { _, last in last }
        )
    }
}

/// One group of look-alike faces: tap a face to leave it out, then name the rest.
private struct FaceGroupRow: View {
    let group: FaceGroupDTO
    let people: [PersonDTO]
    let familyName: String?
    @Binding var excluded: Set<Int>
    let isBusy: Bool
    let assign: (_ faceIds: [Int], _ personId: Int) -> Void
    let dismiss: (_ faceIds: [Int]) -> Void

    private static let cropsShown = 8
    private static let cropSize: CGFloat = 72

    private var includedIds: [Int] {
        group.faces.filter { !excluded.contains($0.id) }.map(\.id)
    }

    private var suggested: PersonDTO? {
        people.first { $0.id == group.suggestedPersonId }
    }

    private var hiddenCount: Int {
        max(group.faces.count - Self.cropsShown, 0)
    }

    private var meta: String {
        let count = includedIds.count
        let faces = count == 1 ? "1 face" : "\(count) faces"
        return count == group.faces.count ? faces : "\(faces) of \(group.faces.count)"
    }

    var body: some View {
        let ids = includedIds
        VStack(alignment: .leading, spacing: 10) {
            if let familyName {
                Text(familyName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.faces.prefix(Self.cropsShown)) { face in
                        crop(face)
                    }
                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.cropSize, height: Self.cropSize)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Text(meta)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let suggested {
                    Button("It's \(suggested.name)") {
                        assign(ids, suggested.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Menu {
                    ForEach(people, id: \.id) { person in
                        Button(person.name) {
                            assign(ids, person.id)
                        }
                    }
                } label: {
                    Text(suggested == nil ? "Who is this?" : "Someone else…")
                }
                .buttonStyle(.bordered)
                .disabled(people.isEmpty)
            }
            .disabled(ids.isEmpty)

            Button("Not someone in the family") {
                dismiss(ids)
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .disabled(ids.isEmpty)
        }
        .disabled(isBusy)
        .padding(.vertical, 4)
    }

    private func crop(_ face: PhotoFaceDTO) -> some View {
        let isExcluded = excluded.contains(face.id)
        return Button {
            if isExcluded {
                excluded.remove(face.id)
            } else {
                excluded.insert(face.id)
            }
        } label: {
            FaceCropView(photoId: face.photoId, box: face.box, size: Self.cropSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(isExcluded ? 0.35 : 1)
                .overlay(alignment: .topTrailing) {
                    if isExcluded {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExcluded ? "Include this face" : "Leave this face out")
        .accessibilityAddTraits(isExcluded ? [] : .isSelected)
    }
}

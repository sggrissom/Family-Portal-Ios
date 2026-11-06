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
                Text("Tap a face to leave it out. Dismiss faces outside the family. If someone is missing from the list, add them to the family first.")
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
                Text("Least certain matches appear first. Confirming a tag helps the app recognize that person.")
            }
        }
    }

    private func autoTagRow(_ face: PhotoFaceDTO, name: String) -> some View {
        let localId = localPhotoIds[face.photoId]
        let openTitle = face.videoFrameMs == nil ? "Open photo" : "Open video"
        let header = HStack(spacing: 12) {
            faceThumbnail(face)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                if localId != nil {
                    Label(openTitle, systemImage: "arrow.up.right")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }

        return VStack(alignment: .leading, spacing: 12) {
            if let localId {
                Button {
                    navigator.push(PhotoRoute(id: localId, startMs: face.videoFrameMs ?? 0))
                } label: {
                    header
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(openTitle) for \(name)")
            } else {
                header
            }

            AdaptiveActionRow {
                Button("Confirm") {
                    Task { await assign([face.id], to: face.personId) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Confirm \(name)")

                Button("Not them") {
                    Task { await reject(face) }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reject the tag for \(name)")
            }
            .controlSize(.large)
            .disabled(isBusy)
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

    private var includedIds: [Int] {
        group.faces.filter { !excluded.contains($0.id) }.map(\.id)
    }

    private var suggested: PersonDTO? {
        people.first { $0.id == group.suggestedPersonId }
    }

    private func selectionSummary(selected: Int) -> String {
        let total = group.faces.count
        if selected == 0 { return "No faces selected" }
        if selected == total { return "\(total) faces" }
        return "\(selected) of \(total) faces selected"
    }

    var body: some View {
        let ids = includedIds
        VStack(alignment: .leading, spacing: 12) {
            if group.faces.count == 1, let face = group.faces.first {
                HStack(spacing: 12) {
                    crop(face)
                    heading(selected: ids.count)
                }
            } else {
                heading(selected: ids.count)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(group.faces) { face in
                            crop(face)
                        }
                    }
                }
                .frame(height: 80)
            }

            AdaptiveActionRow {
                if let person = suggested {
                    Button("Confirm") {
                        assign(ids, person.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Confirm \(person.name)")
                }
                Menu {
                    ForEach(people, id: \.id) { person in
                        Button(person.name) {
                            assign(ids, person.id)
                        }
                    }
                } label: {
                    Text(suggested == nil ? "Choose person…" : "Someone else…")
                }
                .buttonStyle(.bordered)
                .disabled(people.isEmpty)
            }
            .controlSize(.large)
            .disabled(ids.isEmpty)

            Button {
                dismiss(ids)
            } label: {
                Label("Dismiss from review", systemImage: "eye.slash")
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(ids.isEmpty)
        }
        .disabled(isBusy)
        .padding(.vertical, 4)
    }

    private func heading(selected: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let suggested {
                Text("Suggested match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggested.name)
                    .font(.headline)
            } else {
                Text(group.faces.count == 1 ? "Unnamed face" : "Unnamed faces")
                    .font(.headline)
            }
            if group.faces.count != 1 || selected == 0 {
                Text(selectionSummary(selected: selected))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let familyName {
                Text(familyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
            faceThumbnail(face)
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

private func faceThumbnail(_ face: PhotoFaceDTO) -> some View {
    FaceCropView(photoId: face.photoId, box: face.box, frameMs: face.videoFrameMs, size: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
}

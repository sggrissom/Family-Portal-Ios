import SwiftData
import SwiftUI

/// Telling the app who's who — the web's Faces page. Unnamed faces come grouped by likeness, each group with the server's guess when it has one; then the automatic tags, least certain first.
/// Online only (see `FaceReviewService`). Answers apply in place (see `FaceReviewState`); pull to refresh for the server's re-clustered view. Leaving after a change pulls family data, so photos pick up the people the server just put on them.
struct FaceReviewView: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @State private var review: FaceReviewState?
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
    private func content(_ review: FaceReviewState) -> some View {
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
                        assign: { ids, personId in Task { await assign(ids, in: group.id, to: personId) } },
                        dismiss: { ids in Task { await dismiss(ids, in: group.id) } }
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
                    Task { await confirm(face) }
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
        review = FaceReviewState(fresh)
        excluded = []
        publishCount()
    }

    private func publishCount() {
        guard let review else { return }
        navigator.updateFaceReviewCount(enabled: review.enabled, unknownCount: review.unknownCount, autoCount: review.autoCount)
    }

    /// Sends one answer, then applies it to the list in place. A failure, or a list that has run out, reloads from the server.
    private func perform(_ change: () async throws -> String?) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        notice = nil
        defer { isBusy = false }

        do {
            let message = try await change()
            didChange = true
            notice = message
            publishCount()
            if review?.isEmpty == true {
                await load()
            }
        } catch {
            let reason = error.localizedDescription
            await load()
            errorMessage = "\(reason). The list has been reloaded."
        }
    }

    private func assign(_ faceIds: [Int], in groupId: Int, to personId: Int) async {
        guard !faceIds.isEmpty else { return }
        await perform {
            let response = try await service.assign(faceIds: faceIds, to: personId)
            let name = review?.personName(personId) ?? "them"
            review?.removeFromGroup(groupId, faceIds: faceIds)
            review?.recordAssigned(response)
            if let remaining = review?.groups.first(where: { $0.id == groupId }) {
                for face in remaining.faces { excluded.remove(face.id) }
            }
            var message = "Tagged \(name) in \(Self.count(response.assigned, "photo"))."
            if response.skipped > 0 {
                message += " Left \(Self.count(response.skipped, "face")) for review, since \(name) is already confirmed on \(response.skipped == 1 ? "that photo" : "those photos")."
            }
            if response.autoTagged > 0 {
                message += " Found \(name) in \(Self.count(response.autoTagged, "more photo")); pull to refresh to check them."
            }
            return message
        }
    }

    private func dismiss(_ faceIds: [Int], in groupId: Int) async {
        guard !faceIds.isEmpty else { return }
        await perform {
            try await service.dismiss(faceIds: faceIds)
            review?.removeFromGroup(groupId, faceIds: faceIds)
            if let remaining = review?.groups.first(where: { $0.id == groupId }) {
                for face in remaining.faces { excluded.remove(face.id) }
            }
            return nil
        }
    }

    private func confirm(_ face: PhotoFaceDTO) async {
        await perform {
            let response = try await service.assign(faceIds: [face.id], to: face.personId)
            let name = review?.personName(face.personId) ?? "them"
            review?.removeAutoTag(face.id, rejected: false)
            review?.recordAssigned(response)
            var message = "Confirmed \(name)."
            if response.autoTagged > 0 {
                message += " Found \(name) in \(Self.count(response.autoTagged, "more photo"))."
            }
            return message
        }
    }

    private func reject(_ face: PhotoFaceDTO) async {
        await perform {
            try await service.reject(faceIds: [face.id])
            review?.removeAutoTag(face.id, rejected: true)
            return "Removed the tag. The face will wait in “Who is this?”."
        }
    }

    private static func count(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
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
    let group: FaceGroupCard
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

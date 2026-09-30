import SwiftUI

/// The web's `/suggestions` page: each suggested tag as a grid of the photos it fits. A tap leaves a photo out; **Tag N photos** and **Not these** act on the rest in bulk. Pushed from the gallery's toolbar when there is something to review.
/// Online only and never queued. After a change the review is fetched again, and a pull brings the newly tagged photos' tag ids down.
struct TagSuggestionsView: View {
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    /// How many of a group's photos are shown at once — the web's `PHOTOS_PER_GROUP`.
    static let photosPerGroup = 24

    @State private var review: GetTagSuggestionsResponseDTO?
    @State private var isLoading = false
    @State private var excluded: Set<Int> = []
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Copy.tagSuggestions.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                if let review {
                    if review.groups.isEmpty {
                        Text(review.enabled ? Copy.tagSuggestions.emptyEnabled : Copy.tagSuggestions.emptyDisabled)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(review.groups) { group in
                        groupCard(group)
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if !(network?.isConnected ?? true) {
                    Text(Copy.tagSuggestions.offline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(Copy.tagSuggestions.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            review = AnalysisService.shared.cachedTagSuggestions
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    // MARK: - Group

    private func groupCard(_ group: SuggestionGroupDTO) -> some View {
        let shown = TagSuggestionReview.shown(in: group, limit: Self.photosPerGroup)
        let included = TagSuggestionReview.includedIds(in: group, excluded: excluded, limit: Self.photosPerGroup)
        let rest = group.suggestions.count - shown.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(TagColor.color(forHex: group.color))
                    .frame(width: 12, height: 12)
                Text(group.label)
                    .font(.headline)
                Text("\(group.suggestions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(Copy.tagSuggestions.hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(shown) { suggestion in
                    photoCell(suggestion, label: group.label)
                }
            }

            if rest > 0 {
                Text(Copy.tagSuggestions.more(rest))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task { await accept(included, label: group.label) }
                } label: {
                    Text(Copy.tagSuggestions.tagPhotos(included.count, label: group.label))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await reject(included) }
                } label: {
                    Text(Copy.tagSuggestions.reject(all: included.count == shown.count))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
            .disabled(busy || included.isEmpty)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func photoCell(_ suggestion: TagSuggestionDTO, label: String) -> some View {
        let isExcluded = excluded.contains(suggestion.id)
        return Button {
            if isExcluded {
                excluded.remove(suggestion.id)
            } else {
                excluded.insert(suggestion.id)
            }
        } label: {
            RemotePhotoView(remoteId: suggestion.photoId, size: .thumb)
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .opacity(isExcluded ? 0.35 : 1)
                .overlay(alignment: .topTrailing) {
                    if isExcluded {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray)
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExcluded ? "Include this photo" : "Leave this photo out")
        .accessibilityValue(label)
        .accessibilityAddTraits(isExcluded ? [] : .isSelected)
    }

    // MARK: - Actions

    private func reload() async {
        guard network?.isConnected ?? true else { return }
        isLoading = true
        defer { isLoading = false }
        if let fresh = await AnalysisService.shared.tagSuggestions() {
            review = fresh
            excluded = []
        } else if review == nil {
            error = Copy.tagSuggestions.loadFailed
        }
    }

    private func accept(_ ids: [Int], label: String) async {
        await run {
            let updated = try await AnalysisService.shared.acceptTagSuggestions(ids)
            return Copy.tagSuggestions.tagged(updated, label: label)
        }
    }

    private func reject(_ ids: [Int]) async {
        await run {
            try await AnalysisService.shared.rejectTagSuggestions(ids)
            return nil
        }
    }

    private func run(_ action: () async throws -> String?) async {
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do {
            notice = try await action()
            await reload()
            // The review can't say which tag ids the photos ended up with — a catalog label becomes a new family tag on first acceptance — so a pull brings them down.
            await syncService?.pullFamilyData()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The review's selection rules, kept apart from the view so they can be tested.
nonisolated enum TagSuggestionReview {
    static func shown(in group: SuggestionGroupDTO, limit: Int) -> [TagSuggestionDTO] {
        Array(group.suggestions.prefix(limit))
    }

    /// The shown suggestions still included — what the bulk buttons act on. A photo beyond the limit is never acted on unseen.
    static func includedIds(in group: SuggestionGroupDTO, excluded: Set<Int>, limit: Int) -> [Int] {
        shown(in: group, limit: limit).map(\.id).filter { !excluded.contains($0) }
    }
}

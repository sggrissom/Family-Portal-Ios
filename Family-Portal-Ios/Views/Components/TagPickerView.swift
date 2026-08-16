import SwiftUI
import SwiftData

/// Chooses which of the family's tags a photo or milestone carries.
///
/// Every toggle writes the *whole* set — `UpdatePhotoTags` and
/// `UpdateMilestoneTags` detach whatever they are not sent — so the picker holds
/// the record's complete id list and hands all of it back on each change. The
/// queue merges repeated writes for the same record last-wins, which is what
/// keeps four taps offline from becoming four requests.
///
/// The vocabulary itself is read-only here: tags are created, renamed, recoloured
/// and deleted on the web (`CreateTag`/`UpdateTag`/`DeleteTag` have no iOS
/// caller), and this screen only applies what already exists.
struct TagPickerView: View {
    /// Sends the new complete set. Throwing reverts the row: the writes this
    /// calls only *queue* the change, so a failure means nothing was queued at
    /// all and the checkmark would otherwise stand for something that will never
    /// happen.
    ///
    /// `@MainActor` because it reaches `SyncService`, which is, and because it
    /// captures the record it writes — a `@Model` that must not cross isolation.
    let apply: @MainActor ([Int]) async throws -> Void

    @Query private var tags: [FamilyTag]
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    /// Owned by the picker while it is open rather than read back off the record,
    /// so a tap redraws immediately and a pull landing mid-edit cannot reorder the
    /// list under the user's finger.
    @State private var selectedIds: [Int]

    /// `tagRemoteIds` seeds the selection and is not kept: SwiftUI rebuilds this
    /// struct on every parent redraw, and `@State` keeps the first value — which
    /// is the intent, since the picker is authoritative while it is open.
    init(tagRemoteIds: [Int], apply: @escaping @MainActor ([Int]) async throws -> Void) {
        self.apply = apply
        _selectedIds = State(initialValue: tagRemoteIds)
    }

    /// `ListTags` sorts case-insensitively by name; the same order here keeps the
    /// two clients' pickers reading alike.
    private var sortedTags: [FamilyTag] {
        tags.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Ids on the record that no local `FamilyTag` explains — a tag created on
    /// the web since the last pull. They stay in the set and are sent back
    /// untouched; the alternative is untagging a record because this device is a
    /// few minutes behind.
    private var unresolvedCount: Int {
        let known = Set(tags.compactMap { $0.remoteId.flatMap(Int.init) })
        return selectedIds.filter { !known.contains($0) }.count
    }

    var body: some View {
        Group {
            if sortedTags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("This family hasn't created any tags yet. Tags are created on the web.")
                )
            } else {
                List {
                    Section {
                        ForEach(sortedTags) { tag in
                            row(for: tag)
                        }
                    } footer: {
                        if unresolvedCount > 0 {
                            Text(
                                unresolvedCount == 1
                                    ? "1 more tag was added on another device and isn't shown yet. It stays on this item."
                                    : "\(unresolvedCount) more tags were added on another device and aren't shown yet. They stay on this item."
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(for tag: FamilyTag) -> some View {
        let remoteId = tag.remoteId.flatMap(Int.init)
        let isSelected = remoteId.map { selectedIds.contains($0) } ?? false

        Button {
            if let remoteId {
                toggle(remoteId)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(TagColor.color(forHex: tag.colorHex))
                    .frame(width: 12, height: 12)
                Text(tag.name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A tag the pull stored without a usable id can't be sent anywhere; it
        // is still worth listing, so the user can see the vocabulary is intact.
        .disabled(remoteId == nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Toggling matches the web's `onToggleTag`: an id already present is
    /// removed, a new one is appended. Keeping the record's existing order means
    /// a save doesn't reshuffle chips the user never touched.
    private func toggle(_ remoteId: Int) {
        let previous = selectedIds

        if let index = selectedIds.firstIndex(of: remoteId) {
            selectedIds.remove(at: index)
        } else {
            selectedIds.append(remoteId)
        }

        let newIds = selectedIds
        Task {
            do {
                try await apply(newIds)
            } catch {
                selectedIds = previous
                errorPresenter?.report(error, title: "Couldn't Save Tags")
            }
        }
    }
}

import SwiftUI
import SwiftData

/// Chooses which of the family's tags a photo or milestone carries. Every toggle writes the *whole* set — `UpdatePhotoTags` detaches whatever it is not sent.
struct TagPickerView: View {
    let apply: @MainActor ([Int]) async throws -> Void

    @Query private var tags: [FamilyTag]
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Environment(AuthService.self) private var authService: AuthService?

    @State private var selectedIds: [Int]

    /// `tagRemoteIds` seeds the selection and is not kept: the picker is authoritative while it is open.
    init(tagRemoteIds: [Int], apply: @escaping @MainActor ([Int]) async throws -> Void) {
        self.apply = apply
        _selectedIds = State(initialValue: tagRemoteIds)
    }

    /// Only tags of a family the account can add to — plus any already on the record, so what is attached stays visible and can be taken off.
    private var sortedTags: [FamilyTag] {
        let access = authService.access
        return tags
            .filter { tag in
                guard !access.canContribute(tag.familyId) else { return true }
                guard let remoteId = tag.remoteId.flatMap(Int.init) else { return false }
                return selectedIds.contains(remoteId)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Ids on the record that no local `FamilyTag` explains — a tag created on the web since the last pull. They stay in the set and are sent back untouched.
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
                    description: Text("This family hasn't created any tags yet. Add them from Tags in the account menu.")
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
        .disabled(remoteId == nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

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

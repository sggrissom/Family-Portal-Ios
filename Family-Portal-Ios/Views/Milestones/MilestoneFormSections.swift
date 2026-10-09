import SwiftUI

/// What happened, worded for the category, and a quote's context. Shared by the add and edit forms so the two cannot drift apart.
struct MilestoneTextSections: View {
    let category: MilestoneCategory
    @Binding var descriptionText: String
    @Binding var context: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        Section(category.entryPrompt.label) {
            TextField(category.entryPrompt.placeholder, text: $descriptionText, axis: .vertical)
                .lineLimit(2...6)
                .focused(isFocused)
        }

        if category == .quote {
            Section(Copy.milestone.context) {
                TextField(Copy.milestone.contextPlaceholder, text: $context)
            }
        }
    }
}

/// An artwork's own photos, then the person's photos from around the date, offered but never attached until tapped. Shared by the add and edit forms.
struct MilestonePhotoSections: View {
    let category: MilestoneCategory
    @Binding var artwork: [PickedArtwork]
    let suggestedPhotos: [Photo]
    @Binding var selectedPhotoIds: Set<UUID>

    var body: some View {
        if category == .artwork {
            ArtworkPhotosSection(picked: $artwork)
        }

        if !suggestedPhotos.isEmpty {
            Section(Copy.milestone.photosAroundThen) {
                SuggestedPhotosRow(photos: suggestedPhotos, selection: $selectedPhotoIds)
            }
        }
    }
}

/// How both milestone forms ask `SuggestMilestonePhotos`.
enum MilestoneSuggestionLookup {
    /// What the suggestions depend on. A change restarts the lookup, so an answer for older words is never shown.
    static func key(personRemoteId: String?, text: String, day: Date?, isConnected: Bool) -> String {
        [personRemoteId ?? "-", text, day.map { dateToAPIString($0) } ?? "-", String(isConnected)].joined(separator: "|")
    }

    /// Waits for typing to settle, the way the web does. `false` when a newer key cancelled this lookup during the wait.
    static func settle() async -> Bool {
        try? await Task.sleep(for: .milliseconds(600))
        return !Task.isCancelled
    }
}

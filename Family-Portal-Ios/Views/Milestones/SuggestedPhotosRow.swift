import SwiftUI

/// "Photos from around then": `SuggestMilestonePhotos`' answer as a row of thumbnails, each attached or unattached by a tap. Nothing is attached until the user taps — a suggestion never changes the selection on its own. Shared by the add and edit forms.
struct SuggestedPhotosRow: View {
    let photos: [Photo]
    @Binding var selection: Set<UUID>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    let selected = selection.contains(photo.id)
                    Button {
                        if selected {
                            selection.remove(photo.id)
                        } else {
                            selection.insert(photo.id)
                        }
                    } label: {
                        RemotePhotoView(remoteId: photo.remoteId.flatMap(Int.init) ?? 0, size: .thumb)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.accentColor)
                                        .padding(4)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selected ? Copy.milestone.detachPhoto : Copy.milestone.attachPhoto)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Which suggested photos a milestone form offers.
enum MilestonePhotoSuggestions {
    /// The suggestions this device holds and could attach, in the server's order, less the ones the milestone already had when the editor opened — those are in the picker already. The server is asked to leave them out too (`excludeIds`); filtering here as well keeps an older server from offering them.
    static func offered(_ suggested: [Int], choices: [Photo], alreadyAttached: Set<Int>) -> [Photo] {
        RemotePhotoResolution.resolve(suggested.filter { !alreadyAttached.contains($0) }, in: choices)
    }
}

import SwiftUI

/// The attached-photos rows shared by the add and edit milestone forms.
struct MilestonePhotosSection: View {
    @Binding var selectedPhotoIds: [Int]
    @State private var isPicking = false

    var body: some View {
        Section {
            if !selectedPhotoIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedPhotoIds, id: \.self) { photoId in
                            RemotePhotoView(remoteId: photoId, size: .thumb)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        selectedPhotoIds.removeAll { $0 == photoId }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(2)
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                isPicking = true
            } label: {
                Label(
                    selectedPhotoIds.isEmpty ? "Attach Photos" : "Change Photos",
                    systemImage: "photo.on.rectangle"
                )
            }
        } header: {
            Text("Photos")
        }
        .sheet(isPresented: $isPicking) {
            MilestonePhotoPickerView(selectedPhotoIds: $selectedPhotoIds)
        }
    }
}

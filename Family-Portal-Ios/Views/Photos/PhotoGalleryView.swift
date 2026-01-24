import SwiftUI
import SwiftData
import PhotosUI

struct PhotoGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @State private var selectedItem: PhotosPickerItem?
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        NavigationStack {
            ZStack {
                if photos.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Photos",
                        systemImage: "photo.on.rectangle",
                        description: Text("Tap + to add your first photo.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(photos) { photo in
                                NavigationLink(value: photo.id) {
                                    PhotoThumbnailView(imageData: photo.imageData, title: photo.title)
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                if isLoading {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Adding photo...")
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
            .navigationTitle("Photos")
            .navigationDestination(for: UUID.self) { photoId in
                PhotoDetailView(photoId: photoId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                isLoading = true
                Task {
                    defer {
                        isLoading = false
                        selectedItem = nil
                    }
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          UIImage(data: data) != nil else {
                        return
                    }
                    let photo = Photo(
                        title: "",
                        descriptionText: "",
                        photoDate: Date(),
                        imageData: data
                    )
                    modelContext.insert(photo)
                }
            }
        }
    }
}

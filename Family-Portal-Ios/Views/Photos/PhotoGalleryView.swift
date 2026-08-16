import SwiftUI
import SwiftData
import ImageIO
import PhotosUI

struct PhotoGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
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
                                NavigationLink(value: PhotoRoute(id: photo.id)) {
                                    PhotoThumbnailView(imageData: photo.imageData, title: photo.title, remoteId: photo.remoteId)
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
            .navigationDestination(for: PhotoRoute.self) { route in
                PhotoDetailView(photoId: route.id)
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
                        // An iCloud photo that never downloaded, or a format
                        // UIImage won't open. Silence here looked like a tap
                        // that did nothing at all.
                        errorPresenter?.report(
                            message: "That photo couldn't be read. If it's stored in iCloud, open it in Photos first and try again.",
                            title: "Couldn't Add Photo"
                        )
                        return
                    }
                    let photo = Photo(
                        title: "",
                        descriptionText: "",
                        photoDate: Self.captureDate(from: data) ?? Date(),
                        imageData: data
                    )
                    modelContext.insert(photo)
                    try? modelContext.save()
                    do {
                        try await syncService?.uploadPhoto(photo)
                    } catch {
                        errorPresenter?.report(error, title: "Couldn't Add Photo")
                    }
                }
            }
        }
    }

    /// Reads the capture date out of the picked image's own EXIF. Deliberately
    /// avoids `PHAsset`, which needs photo-library authorization the picker
    /// itself does not; the backend does the same thing for `inputType: "auto"`.
    private static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = (exif[kCGImagePropertyExifDateTimeOriginal]
                              ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        else {
            return nil
        }

        return exifDateFormatter.date(from: original)
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}

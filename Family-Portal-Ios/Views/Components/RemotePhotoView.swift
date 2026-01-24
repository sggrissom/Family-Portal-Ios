import SwiftUI

struct RemotePhotoView: View {
    let remoteId: Int
    let size: PhotoSizeVariant

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        let service = PhotoSyncService()
        guard let url = await service.photoURL(remoteId: remoteId, size: size) else {
            isLoading = false
            hasFailed = true
            return
        }

        let token = await APIClient.shared.getAccessToken()

        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let uiImage = UIImage(data: data) else {
                hasFailed = true
                isLoading = false
                return
            }
            image = uiImage
            isLoading = false
        } catch {
            hasFailed = true
            isLoading = false
        }
    }
}

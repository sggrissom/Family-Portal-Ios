import SwiftUI

struct RemotePhotoView: View {
    let remoteId: Int
    let size: PhotoSizeVariant
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasFailed = false

    init(remoteId: Int, size: PhotoSizeVariant, contentMode: ContentMode = .fill) {
        self.remoteId = remoteId
        self.size = size
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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

        // Photos are fetched with the raw token rather than through
        // `APIClient.request`, so they get neither its proactive refresh nor its
        // retry-on-401 unless asked for both here. Without the refresh, a session
        // that crosses the JWT expiry while the app stays foregrounded renders
        // every photo as a placeholder until the next relaunch.
        await APIClient.shared.ensureFreshAccessToken()

        var outcome = await fetch(url)

        // A 401 despite the check above means the token went stale inside the
        // margin. One forced refresh and retry, mirroring `retryOnAuthFailure`.
        if case .unauthorized = outcome {
            try? await APIClient.shared.refreshAccessToken()
            outcome = await fetch(url)
        }

        switch outcome {
        case .loaded(let uiImage):
            image = uiImage
        case .unauthorized, .failed:
            hasFailed = true
        }
        isLoading = false
    }

    private enum FetchOutcome {
        case loaded(UIImage)
        case unauthorized
        case failed
    }

    private func fetch(_ url: URL) async -> FetchOutcome {
        var request = URLRequest(url: url)
        if let token = await APIClient.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed
            }
            if httpResponse.statusCode == 401 {
                return .unauthorized
            }
            guard (200...299).contains(httpResponse.statusCode),
                  let uiImage = UIImage(data: data) else {
                return .failed
            }
            return .loaded(uiImage)
        } catch {
            return .failed
        }
    }
}

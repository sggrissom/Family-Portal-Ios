import AVFoundation
import AVKit
import Combine
import OSLog
import SwiftUI

/// One video's playback on its page: the web's `VideoPlayer`. Links come from `GetVideoPlayback` each time the page opens and are never stored; a link that lapses mid-viewing is renewed and playback carries on from the same place.
@MainActor
@Observable
final class VideoPlayerModel {
    enum Phase: Equatable {
        case loading
        /// Video needs the server; the poster is all there is offline.
        case offline
        case processing
        /// The server couldn't prepare it, in its own words when it gave any.
        case failed(reason: String)
        case ready
        /// The link answers but this device can't decode the file.
        case unsupported
        /// The connection dropped mid-viewing; Try again renews and resumes.
        case stopped
        /// `GetVideoPlayback` itself failed.
        case unavailable
    }

    private(set) var phase: Phase = .loading
    private(set) var playback: GetVideoPlaybackResponseDTO?
    private(set) var player: AVPlayer?
    /// Width over height once the file has said, for sizing the player; a portrait clip should not sit in a letterboxed 16:9 box.
    private(set) var aspectRatio: CGFloat?
    /// Asked once the video is ready; nil until then, or when the server couldn't say.
    private(set) var transcript: GetVideoTranscriptResponseDTO?
    /// Where playback is, in seconds: for resuming after a renewal, and for the transcript's current line.
    private(set) var position: Double = 0
    /// Off until asked for, as on the web.
    var showsCaptions = false

    /// The line to draw over the video, when captions are on and someone is speaking.
    var caption: String? {
        guard showsCaptions, let transcript, transcript.status == GetVideoTranscriptResponseDTO.Status.done else { return nil }
        return VideoTranscript.caption(transcript.segments, seconds: position)
    }

    let photoId: Int
    private let apiClient: APIClient

    private var renewals = 0
    private var wasPlaying = false
    private var resume: (seconds: Double, playing: Bool)?
    private var handlingFailure = false
    private var statusTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var failureObserver: NSObjectProtocol?

    /// How long to wait between asks while the server is still preparing the video.
    private static let processingPollInterval: Duration = .seconds(5)

    /// `startMs` opens the video there, paused: a search match or a face's frame, the web's `?t=`.
    init(photoId: Int, startMs: Int = 0, apiClient: APIClient = .shared) {
        self.photoId = photoId
        self.apiClient = apiClient
        if startMs > 0 {
            position = Double(startMs) / 1000
            resume = (position, false)
        }
    }

    /// Fetches the links, and keeps asking while the video is still processing. Called from the view's `.task`, so leaving the page stops the asking.
    func load(isConnected: Bool) async {
        guard isConnected else {
            if player == nil { phase = .offline }
            return
        }
        guard player == nil else { return }
        phase = .loading
        while !Task.isCancelled {
            guard let fresh = await fetch() else {
                phase = .unavailable
                return
            }
            await apply(fresh)
            guard phase == .processing else {
                if phase == .ready { await loadTranscript() }
                return
            }
            try? await Task.sleep(for: Self.processingPollInterval)
        }
    }

    /// After a dropped connection or a failed fetch: a fresh link, from where playback was.
    func retry() async {
        renewals = 0
        await renew()
    }

    func stop() {
        player?.pause()
    }

    /// From a transcript line: there, and playing.
    func seek(to seconds: Double) {
        guard let player else { return }
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    /// Like the links, asked on each visit and never stored. A failure only means no transcript.
    private func loadTranscript() async {
        guard transcript == nil else { return }
        do {
            transcript = try await apiClient.callRPC(.getVideoTranscript, payload: GetVideoTranscriptRequestDTO(id: photoId))
        } catch {
            AppLog.ui.error("Couldn't load the transcript of video \(self.photoId): \(String(describing: error), privacy: .public)")
        }
    }

    private func fetch() async -> GetVideoPlaybackResponseDTO? {
        do {
            return try await apiClient.callRPC(.getVideoPlayback, payload: GetVideoPlaybackRequestDTO(id: photoId))
        } catch {
            AppLog.ui.error("Couldn't load video \(self.photoId): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func apply(_ fresh: GetVideoPlaybackResponseDTO) async {
        playback = fresh
        switch fresh.status {
        case 1:
            phase = .processing
        case 0 where !fresh.playbackUrl.isEmpty:
            await start(fresh.playbackUrl)
        case 0:
            // Ready, but the server's storage is off: there is nothing to stream.
            phase = .unavailable
        default:
            phase = .failed(reason: fresh.processingError)
        }
    }

    private func renew() async {
        resume = (position, wasPlaying)
        guard let fresh = await fetch() else {
            phase = player == nil ? .unavailable : .stopped
            return
        }
        await apply(fresh)
    }

    // MARK: - The player

    private func start(_ link: String) async {
        let baseURL = await apiClient.getBaseURL()
        guard let url = APIClient.mediaURL(link, baseURL: baseURL) else {
            phase = .unavailable
            return
        }
        // No cookies: the app keeps its own session cookies in the shared jar AVFoundation reads by default, and a minted link must go out without them.
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: [HTTPCookie]()])
        let item = AVPlayerItem(asset: asset)
        observe(item)

        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            let player = AVPlayer(playerItem: item)
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                let seconds = time.seconds
                MainActor.assumeIsolated {
                    guard let self, let player = self.player, player.currentItem?.status == .readyToPlay else { return }
                    self.position = seconds
                    self.wasPlaying = player.timeControlStatus != .paused
                }
            }
            self.player = player
        }
        // Plays with the ring switch on silent, like any video app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        phase = .ready
    }

    /// Watched from a task on the main actor rather than a KVO closure, which would be called on whatever thread AVFoundation chose.
    private func observe(_ item: AVPlayerItem) {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            for await status in item.publisher(for: \.status).values {
                guard let self, !Task.isCancelled else { return }
                self.statusChanged(status, isNetworkError: VideoPlayback.isNetworkError(item.error), presentationSize: item.presentationSize)
            }
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] note in
            let isNetwork = VideoPlayback.isNetworkError(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.failed(isNetworkError: isNetwork) }
            }
        }
    }

    private func statusChanged(_ status: AVPlayerItem.Status, isNetworkError: Bool, presentationSize: CGSize) {
        switch status {
        case .readyToPlay:
            if presentationSize.width > 0, presentationSize.height > 0 {
                aspectRatio = presentationSize.width / presentationSize.height
            }
            if let resume {
                self.resume = nil
                if resume.seconds > 0 {
                    player?.seek(to: CMTime(seconds: resume.seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                if resume.playing { player?.play() }
            }
        case .failed:
            Task { await failed(isNetworkError: isNetworkError) }
        default:
            break
        }
    }

    /// Renews a lapsed or refused link and resumes; otherwise says what went wrong.
    private func failed(isNetworkError: Bool) async {
        guard !handlingFailure, let playback else { return }
        handlingFailure = true
        defer { handlingFailure = false }

        let probe = await apiClient.probeMedia(playback.playbackUrl)
        let problem = VideoPlayback.classify(
            isNetworkError: isNetworkError,
            probeStatus: probe,
            now: Date(),
            expiresAt: playback.expiresAt
        )
        if problem == .expired, renewals < VideoPlayback.maxRenewals {
            renewals += 1
            await renew()
            return
        }
        player?.pause()
        phase = problem == .unsupported ? .unsupported : .stopped
    }
}

/// The player, or the poster with a line saying why there is no player: still processing, refused, offline, or not playable here. Shown on a video's page in place of the photo.
struct VideoPlayerSection: View {
    /// The mirror's record, nil for a video opened by server id before the mirror holds it.
    let photo: Photo?

    @Environment(NetworkMonitor.self) private var network
    @State private var model: VideoPlayerModel

    init(photo: Photo?, remoteId: Int, startMs: Int = 0) {
        self.photo = photo
        _model = State(initialValue: VideoPlayerModel(photoId: remoteId, startMs: startMs))
    }

    var body: some View {
        VStack(spacing: 12) {
            if let player = model.player, model.phase == .ready || model.phase == .stopped {
                VideoPlayerController(player: player, caption: model.caption)
                    .aspectRatio(model.aspectRatio ?? 16 / 9, contentMode: .fit)
                    .frame(maxHeight: 560)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                poster
            }
            note
            if let transcript = model.transcript, model.player != nil {
                if transcript.status == GetVideoTranscriptResponseDTO.Status.done, !transcript.segments.isEmpty {
                    captionsToggle
                }
                VideoTranscriptView(transcript: transcript, position: model.position) { seconds in
                    model.seek(to: seconds)
                }
            }
        }
        .padding(.horizontal)
        .task(id: network.isConnected) {
            await model.load(isConnected: network.isConnected)
        }
        .onChange(of: model.playback?.status) { _, status in
            // The mirror would catch up on its next pull; the badge and widgets needn't wait for it.
            if let status, let photo, status != photo.status { photo.status = status }
        }
        .onDisappear { model.stop() }
    }

    private var poster: some View {
        RemotePhotoView(remoteId: model.photoId, size: .xlarge, contentMode: .fit)
            .scaledToFit()
            .frame(maxWidth: .infinity, minHeight: 200)
            .overlay {
                if model.phase == .loading {
                    ProgressView()
                } else if model.phase == .processing {
                    ProgressView()
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var note: some View {
        switch model.phase {
        case .loading, .ready:
            EmptyView()
        case .offline:
            message(Copy.video.offlineTitle, Copy.video.offlineBody, systemImage: "icloud.slash")
        case .processing:
            message(Copy.video.processingTitle, Copy.video.processingBody, systemImage: "clock")
        case .failed(let reason):
            message(Copy.video.failedTitle, reason.isEmpty ? Copy.video.failedFallback : reason, systemImage: "exclamationmark.triangle")
        case .unsupported:
            message(Copy.video.unsupportedTitle, Copy.video.unsupportedBody, systemImage: "film")
        case .stopped:
            VStack(spacing: 8) {
                message(Copy.video.stoppedTitle, Copy.video.stoppedBody, systemImage: "wifi.exclamationmark")
                retryButton
            }
        case .unavailable:
            VStack(spacing: 8) {
                message(Copy.video.unavailableTitle, Copy.video.unavailableBody, systemImage: "exclamationmark.icloud")
                retryButton
            }
        }
    }

    private var captionsToggle: some View {
        Button {
            model.showsCaptions.toggle()
        } label: {
            Label(Copy.video.captions, systemImage: model.showsCaptions ? "captions.bubble.fill" : "captions.bubble")
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(model.showsCaptions ? .accentColor : .secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(model.showsCaptions ? Copy.video.captionsOff : Copy.video.captionsOn)
    }

    private var retryButton: some View {
        Button {
            Task { await model.retry() }
        } label: {
            Label(Copy.video.tryAgain, systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(!network.isConnected)
    }

    private func message(_ title: String, _ body: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The system player — controls, full screen, AirPlay — around an `AVPlayer` the model owns. Captions are drawn in its content overlay, between the video and the controls, so they follow it into full screen: AVPlayer reads WebVTT only from inside HLS, and playback here is a plain MP4.
private struct VideoPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let caption: String?

    func makeCoordinator() -> CaptionOverlay { CaptionOverlay() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        if let overlay = controller.contentOverlayView {
            context.coordinator.install(in: overlay)
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        context.coordinator.show(caption)
    }
}

/// White text on a dark band near the bottom of the picture, like system captions.
private final class CaptionOverlay {
    private let label = UILabel()
    private let band = UIView()

    func install(in overlay: UIView) {
        label.numberOfLines = 3
        label.textAlignment = .center
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .callout)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false

        band.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        band.layer.cornerRadius = 6
        band.isUserInteractionEnabled = false
        band.isHidden = true
        band.translatesAutoresizingMaskIntoConstraints = false
        band.addSubview(label)
        overlay.addSubview(band)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: band.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: band.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: band.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: band.bottomAnchor, constant: -4),
            band.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            band.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 16),
            band.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -16),
            band.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -48),
        ])
    }

    func show(_ caption: String?) {
        label.text = caption
        band.isHidden = caption == nil
    }
}

/// What was said, under the player: tap a line to play from it, and the line playing is marked. Folded away until opened, as on the web; fixing lines stays on the web.
private struct VideoTranscriptView: View {
    let transcript: GetVideoTranscriptResponseDTO
    let position: Double
    let onSeek: (Double) -> Void

    var body: some View {
        if transcript.status == GetVideoTranscriptResponseDTO.Status.done, !transcript.segments.isEmpty {
            DisclosureGroup {
                lines
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.video.transcript)
                        .font(.subheadline.weight(.semibold))
                    if transcript.automatic {
                        Text(Copy.video.transcriptAutomatic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if transcript.pending {
            Text(Copy.video.transcriptPending)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lines: some View {
        let active = VideoTranscript.currentSegment(transcript.segments, seconds: position)
        return LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(transcript.segments.enumerated()), id: \.offset) { index, segment in
                let time = VideoDuration.format(milliseconds: segment.startMs)
                let unsure = transcript.automatic && segment.confidence < VideoTranscript.lowConfidence
                Button {
                    onSeek(Double(segment.startMs) / 1000)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tint)
                        Text(segment.text)
                            .font(.subheadline)
                            .italic(unsure)
                            .foregroundStyle(unsure ? Color.secondary : Color.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(index == active ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Copy.video.transcriptLine(time))
            }
        }
        .padding(.top, 8)
    }
}

import Observation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// The share sheet's state: the files being copied into the inbox, and what is chosen for them.
///
/// Copying starts as soon as the sheet opens, so **Add** has nothing left to wait for by the time the choices are made. Files are copied by URL and never loaded into memory: the extension gets about 120 MB, and a video is often more than that.
@MainActor
@Observable
final class ShareModel {

    enum Phase {
        case signedOut
        case preparing
        case ready
        /// Nothing shared could be copied.
        case unreadable
    }

    private(set) var phase: Phase
    let people: [WidgetPerson]
    let tags: [WidgetTag]
    var personIds: Set<Int> = []
    var tagIds: Set<Int> = []
    var caption = ""

    let total: Int
    private(set) var copied: [ShareManifest.Item] = []
    private(set) var failed = 0

    var onFinish: ((_ added: Bool) -> Void)?

    private let providers: [NSItemProvider]
    private let snapshot: WidgetSnapshot?
    private let inbox: ShareInbox?
    private var folder: URL?
    private var copying: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.familyrecord.ios", category: "share")

    init(providers: [NSItemProvider], snapshot: WidgetSnapshot?, inbox: ShareInbox?) {
        self.providers = providers.filter { Self.kind(of: $0) != nil }
        self.snapshot = snapshot
        self.inbox = inbox
        people = snapshot?.people ?? []
        tags = snapshot?.tags ?? []
        total = self.providers.count
        // No snapshot means no one is signed in, or the app hasn't run since installing: there's no roster to offer and no account to file the share under.
        phase = snapshot == nil || inbox == nil ? .signedOut : .preparing
    }

    var photoCount: Int { providers.filter { Self.kind(of: $0) == .photo }.count }
    var videoCount: Int { providers.filter { Self.kind(of: $0) == .video }.count }

    func start() {
        guard phase == .preparing, let inbox else { return }
        copying = Task {
            do {
                let folder = try inbox.makeShareFolder()
                self.folder = folder
                for (index, provider) in providers.enumerated() {
                    guard !Task.isCancelled else { return }
                    guard let kind = Self.kind(of: provider) else { continue }
                    do {
                        copied.append(try await Self.copy(provider, kind: kind, index: index, into: folder))
                    } catch {
                        Self.log.error("Couldn't copy a shared item: \(String(describing: error), privacy: .public)")
                        failed += 1
                    }
                }
            } catch {
                Self.log.error("Couldn't make a share folder: \(String(describing: error), privacy: .public)")
                failed = total
            }
            phase = copied.isEmpty ? .unreadable : .ready
        }
    }

    func add() {
        guard phase == .ready, let inbox, let folder, let snapshot else { return }
        let manifest = ShareManifest(
            createdAt: Date(),
            ownerUserId: snapshot.ownerUserId,
            personIds: people.map(\.id).filter { personIds.contains($0) },
            tagIds: tags.map(\.id).filter { tagIds.contains($0) },
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            items: copied
        )
        do {
            try inbox.writeManifest(manifest, in: folder)
            onFinish?(true)
        } catch {
            Self.log.error("Couldn't write a share's manifest: \(String(describing: error), privacy: .public)")
            inbox.remove(folder)
            onFinish?(false)
        }
    }

    func cancel() {
        copying?.cancel()
        if let folder {
            inbox?.remove(folder)
        }
        onFinish?(false)
    }

    // MARK: - Copying

    private enum CopyFailure: Error {
        case unreadable
    }

    /// A movie is checked first: a Live Photo's provider can conform to both, and the still is what an in-app pick of it imports.
    nonisolated private static func kind(of provider: NSItemProvider) -> ShareManifest.Item.Kind? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) { return .photo }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) { return .video }
        return nil
    }

    /// Copies one item into its own subfolder under its original name, so a video keeps the extension the server reads its type from.
    nonisolated private static func copy(_ provider: NSItemProvider, kind: ShareManifest.Item.Kind, index: Int, into folder: URL) async throws -> ShareManifest.Item {
        let base: UTType = kind == .video ? .movie : .image
        // The most specific type the provider has — HEIC rather than a re-encoded JPEG, so the original bytes are what's kept.
        let typeIdentifier = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: base) == true } ?? base.identifier
        let itemFolder = folder.appendingPathComponent(String(index), isDirectory: true)
        try FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)

        let destination: URL = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                // The file only lasts until this returns, so it is copied here and now.
                guard let url else {
                    continuation.resume(throwing: error ?? CopyFailure.unreadable)
                    return
                }
                let name = url.lastPathComponent.isEmpty ? "item" : url.lastPathComponent
                let destination = itemFolder.appendingPathComponent(name, isDirectory: false)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return ShareManifest.Item(
            file: "\(index)/\(destination.lastPathComponent)",
            kind: kind,
            captureDate: kind == .photo ? CaptureDate.from(fileURL: destination) : nil
        )
    }
}

/// The share sheet: the people, caption and tags the in-app photo form offers, for the whole share. What's chosen goes into the inbox with the files, and the app applies it when it imports them.
struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ShareCopy.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ShareCopy.cancel) { model.cancel() }
                    }
                    if model.phase == .preparing || model.phase == .ready {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(ShareCopy.add) { model.add() }
                                .disabled(model.phase != .ready)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .signedOut:
            ContentUnavailableView(
                ShareCopy.signedOut,
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text(ShareCopy.signedOutDetail)
            )
        case .unreadable:
            ContentUnavailableView(
                ShareCopy.nothingReadable,
                systemImage: "exclamationmark.triangle",
                description: Text(ShareCopy.nothingReadableDetail)
            )
        case .preparing, .ready:
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ShareCopy.summary(photos: model.photoCount, videos: model.videoCount))
                        .font(.headline)
                    if model.phase == .preparing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(ShareCopy.preparing(model.copied.count + model.failed, of: model.total))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else if model.failed > 0 {
                        Text(ShareCopy.skipped(model.failed))
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            } footer: {
                Text(ShareCopy.addedLater)
            }

            if !model.people.isEmpty {
                Section(ShareCopy.whoIsIn) {
                    ForEach(model.people) { person in
                        toggleRow(person.name, isOn: model.personIds.contains(person.id)) {
                            model.personIds.formSymmetricDifference([person.id])
                        }
                    }
                }
            }

            Section(ShareCopy.caption) {
                TextField(ShareCopy.captionPlaceholder, text: $model.caption)
            }

            if !model.tags.isEmpty {
                Section(ShareCopy.tags) {
                    ForEach(model.tags) { tag in
                        toggleRow(tag.name, isOn: model.tagIds.contains(tag.id)) {
                            model.tagIds.formSymmetricDifference([tag.id])
                        }
                    }
                }
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

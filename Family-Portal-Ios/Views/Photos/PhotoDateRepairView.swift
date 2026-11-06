import Foundation
import Photos
import SwiftData
import SwiftUI

struct PhotoDateRepairView: View {
    let photos: [Photo]

    @Environment(AuthService.self) private var auth
    @Environment(NetworkMonitor.self) private var network
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID> = []
    @State private var approved: Set<UUID> = []
    @State private var review: Review?
    @State private var isChecking = false
    @State private var isSaving = false
    @State private var notice: String?

    private let selectionLimit = 20

    private struct Proposal: Identifiable {
        let photo: Photo
        let previousDate: Date
        let newDate: Date

        var id: UUID { photo.id }
    }

    private struct Review {
        var proposals: [Proposal] = []
        var unavailable = 0
        var unchanged = 0
        var unmatched = 0
    }

    private var candidates: [Photo] { photos.filter(canRepair) }

    var body: some View {
        List {
            if let notice {
                Section { Text(notice).foregroundStyle(.secondary) }
            }
            if isChecking {
                ProgressView("Checking photo originals…")
            } else if let review {
                reviewRows(review)
            } else if candidates.isEmpty {
                ContentUnavailableView(
                    "No Photos to Repair",
                    systemImage: "photo.on.rectangle",
                    description: Text("Choose a gallery filter with photos you can edit.")
                )
            } else {
                Section {
                    ForEach(candidates) { photo in
                        selectionRow(photo, isSelected: selected.contains(photo.id)) {
                            if selected.contains(photo.id) {
                                selected.remove(photo.id)
                            } else if selected.count < selectionLimit {
                                selected.insert(photo.id)
                            }
                        }
                        .disabled(!selected.contains(photo.id) && selected.count >= selectionLimit)
                    }
                } header: {
                    Text("Choose Photos")
                } footer: {
                    Text("Select up to \(selectionLimit) photos. Family Record compares their originals with Apple Photos and shows any date changes before saving.")
                }
            }
        }
        .navigationTitle("Repair Photo Dates")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else if review != nil {
                    Button("Apply (\(approved.count))") {
                        isSaving = true
                        Task { await apply() }
                    }
                    .disabled(approved.isEmpty)
                } else if !isChecking {
                    Button("Check (\(selected.count))") { isChecking = true }
                        .disabled(selected.isEmpty)
                }
            }
        }
        .task(id: isChecking) {
            guard isChecking else { return }
            await check()
        }
    }

    @ViewBuilder
    private func reviewRows(_ review: Review) -> some View {
        Section("Proposed Changes") {
            if review.proposals.isEmpty {
                Text("No date changes to apply.").foregroundStyle(.secondary)
            }
            ForEach(review.proposals) { proposal in
                selectionRow(proposal.photo, isSelected: approved.contains(proposal.id), proposal: proposal) {
                    if approved.contains(proposal.id) {
                        approved.remove(proposal.id)
                    } else {
                        approved.insert(proposal.id)
                    }
                }
                .disabled(isSaving)
            }
        }
        Section {
            if review.unchanged > 0 { Text("Already correct: \(review.unchanged)") }
            if review.unmatched > 0 { Text("No exact Photos match: \(review.unmatched)") }
            if review.unavailable > 0 { Text("Original unavailable: \(review.unavailable)") }
            Button("Choose Photos Again") {
                self.review = nil
                notice = nil
            }
            .disabled(isSaving)
        }
    }

    private func selectionRow(_ photo: Photo, isSelected: Bool, proposal: Proposal? = nil, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                PhotoThumbnailView(imageData: photo.imageData, title: "", remoteId: photo.remoteId)
                    .frame(width: 46, height: 46)
                    .clipped()
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(photo.title.isEmpty ? "Photo" : photo.title)
                        .foregroundStyle(.primary)
                    if let proposal {
                        Text("From \(proposal.previousDate.displayDay().formatted(date: .abbreviated, time: .omitted))")
                        Text("To \(proposal.newDate.displayDay().formatted(date: .abbreviated, time: .omitted))")
                    } else {
                        Text(photo.dateText(.abbreviated))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func canRepair(_ photo: Photo) -> Bool {
        !photo.isDeleted && !photo.isVideo && photo.hasExactDate && auth.access.canContribute(to: photo)
    }

    private func check() async {
        defer { isChecking = false }
        notice = nil
        let picks = candidates.filter { selected.contains($0.id) }.map { (photo: $0, date: $0.photoDate) }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            notice = "Allow Family Record to read Photos in Settings to look up the original dates."
            return
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var downloads: [DownloadedOriginal] = []
        defer {
            for download in downloads { download.remove() }
            try? FileManager.default.removeItem(at: folder)
        }
        var result = Review()
        var files: [UUID: URL] = [:]
        for (photo, _) in picks {
            guard !Task.isCancelled else { return }
            do {
                if let data = photo.imageData {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let file = folder.appendingPathComponent(photo.id.uuidString)
                    try data.write(to: file)
                    files[photo.id] = file
                } else if network.isConnected, let serverId = photo.serverId {
                    let original = try await APIClient.shared.downloadOriginal(photoId: serverId)
                    downloads.append(original)
                    files[photo.id] = original.fileURL
                } else {
                    result.unavailable += 1
                }
            } catch {
                result.unavailable += 1
            }
        }

        guard !Task.isCancelled else { return }
        let dates = await SharedPhotoDates.resolve(picks.compactMap { files[$0.photo.id] }, onlyMissingEmbeddedDates: false)
        guard !Task.isCancelled else { return }
        for (photo, previousDate) in picks {
            guard let file = files[photo.id] else { continue }
            guard let date = dates[file]?.localRecordDay() else {
                result.unmatched += 1
                continue
            }
            if date == previousDate.recordDate {
                result.unchanged += 1
            } else {
                result.proposals.append(Proposal(photo: photo, previousDate: previousDate, newDate: date))
            }
        }
        review = result
        approved = Set(result.proposals.map(\.id))
    }

    private func apply() async {
        defer { isSaving = false }
        guard let review, let userId = auth.currentUser?.id else { return }
        var queued: Set<UUID> = []
        var stale: Set<UUID> = []
        var failed = 0
        for proposal in review.proposals where approved.contains(proposal.id) {
            let photo = proposal.photo
            guard auth.currentUser?.id == userId, canRepair(photo), photo.photoDate == proposal.previousDate else {
                stale.insert(proposal.id)
                continue
            }
            do {
                try await sync.updatePhoto(photo, keepingDate: false, recordTime: .exact(day: proposal.newDate.recordDayKey))
                queued.insert(proposal.id)
            } catch {
                failed += 1
            }
        }
        let settled = queued.union(stale)
        self.review?.proposals.removeAll { settled.contains($0.id) }
        approved.subtract(settled)
        selected.subtract(settled)
        notice = [
            queued.isEmpty ? nil : "Queued date changes: \(queued.count).",
            stale.isEmpty ? nil : "Skipped changed or unavailable photos: \(stale.count).",
            failed == 0 ? nil : "Couldn't queue \(failed) changes. Try applying them again."
        ].compactMap { $0 }.joined(separator: " ")
    }
}

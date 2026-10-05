import SwiftUI
import SwiftData

/// A batch of picked photos, for the form that opens over their import.
struct PhotoBatch: Identifiable {
    let id = UUID()
    let entryIds: [UUID]
    /// Preselected only when the batch was started from a person's own page — never inherited from anywhere else.
    let preselectedPersonIds: Set<UUID>
}

/// Upload first, then the optional details: **Who's in these?**, a caption and tags for the whole batch, and each photo's own date and status.
/// The photos are already read and queued when this opens. **Done** applies the choices and closes; it never cancels or discards an upload, which is why the sheet cannot be swiped away — there is nothing to cancel.
struct PhotoBatchFormView: View {
    let batch: PhotoBatch
    let importer: PhotoImporter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?

    @Query private var photos: [Photo]

    @State private var personIds: Set<UUID>
    @State private var caption = ""
    @State private var tagRemoteIds: [Int] = []
    @State private var dates: [UUID: Date] = [:]
    @State private var editingDateFor: UUID?

    init(batch: PhotoBatch, importer: PhotoImporter) {
        self.batch = batch
        self.importer = importer
        _personIds = State(initialValue: batch.preselectedPersonIds)
    }

    private var entries: [PhotoImporter.ImportEntry] {
        batch.entryIds.compactMap { importer.entries[$0] }
    }

    /// "for all 5 photos" — the choices apply to the whole batch, and say so.
    private var scope: String {
        entries.count == 1 ? "" : " (all \(entries.count))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("\(Copy.photos.whoIsIn)\(scope)") {
                    PersonChips(selection: $personIds, contributableOnly: true)
                }

                Section("\(Copy.photos.caption)\(scope)") {
                    TextField(Copy.photos.captionPlaceholder, text: $caption)
                }

                Section {
                    NavigationLink {
                        TagPickerView(tagRemoteIds: tagRemoteIds) { tagRemoteIds = $0 }
                    } label: {
                        LabeledContent("\(Copy.photos.tags)\(scope)", value: tagRemoteIds.isEmpty ? "" : "\(tagRemoteIds.count)")
                    }
                }

                Section(Copy.photos.title) {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
            .navigationTitle(Copy.photos.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.photos.done) { done() }
                }
            }
            .interactiveDismissDisabled()
            .sheet(item: Binding(
                get: { editingDateFor.map(DateEdit.init) },
                set: { editingDateFor = $0?.id }
            )) { edit in
                dateEditor(for: edit.id)
            }
        }
    }

    private struct DateEdit: Identifiable {
        let id: UUID
    }

    private func photo(for entry: PhotoImporter.ImportEntry) -> Photo? {
        guard let photoId = entry.photoId else { return nil }
        return photos.first { $0.id == photoId }
    }

    @ViewBuilder
    private func row(_ entry: PhotoImporter.ImportEntry) -> some View {
        let photo = photo(for: entry)
        HStack(spacing: 12) {
            PhotoThumbnailView(imageData: photo?.imageData, title: photo?.title ?? "", remoteId: photo?.remoteId)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                dateLine(entry, photo: photo)
                status(entry, photo: photo)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func dateLine(_ entry: PhotoImporter.ImportEntry, photo: Photo?) -> some View {
        if let photo {
            HStack(spacing: 4) {
                if let changed = dates[entry.id] {
                    Text("\(Copy.photos.taken) \(changed.formatted(date: .abbreviated, time: .omitted))")
                } else if entry.hasCaptureDate {
                    Text("\(Copy.photos.taken) \(photo.photoDate.displayDay().formatted(date: .abbreviated, time: .omitted))")
                } else {
                    Text("No date in photo: using today")
                        .foregroundStyle(.orange)
                }
                Button(Copy.photos.change) { editingDateFor = entry.id }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func status(_ entry: PhotoImporter.ImportEntry, photo: Photo?) -> some View {
        if entry.failed {
            HStack(spacing: 8) {
                Label(Copy.photos.failed, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Retry") {
                    importer.retry(entry.id, into: modelContext, syncService: syncService)
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
        } else if photo?.remoteId != nil {
            Label(Copy.photos.uploaded, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label(Copy.photos.uploading, systemImage: "arrow.up.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dateEditor(for entryId: UUID) -> some View {
        let current = dates[entryId]
            ?? importer.entries[entryId].flatMap { photo(for: $0)?.photoDate.displayDay() }
            ?? Date()
        return NavigationStack {
            DatePicker(
                Copy.when.date,
                selection: Binding(get: { dates[entryId] ?? current }, set: { dates[entryId] = $0 }),
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle(Copy.when.date)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.photos.done) { editingDateFor = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func done() {
        var choices = PhotoImporter.BatchChoices()
        choices.personIds = personIds
        choices.caption = caption
        choices.tagRemoteIds = tagRemoteIds
        choices.dates = dates
        importer.apply(choices, to: batch.entryIds, context: modelContext, syncService: syncService)
        dismiss()
    }
}

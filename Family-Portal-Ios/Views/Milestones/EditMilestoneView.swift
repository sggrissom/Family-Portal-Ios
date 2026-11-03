import SwiftUI
import SwiftData

struct EditMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(NetworkMonitor.self) private var network

    let milestone: Milestone

    @State private var descriptionText: String
    @State private var category: MilestoneCategory
    @State private var context: String
    @State private var date: Date
    /// The date once the server takes approximate dates; compared with `initialRecordWhen` so an untouched date isn't resent.
    @State private var recordWhen: RecordWhenEntry
    private let initialRecordWhen: RecordWhenEntry
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var didSeedSelection = false
    @State private var isReadingPhotos = false
    @State private var newPhotos: [PickedMilestonePhoto] = []
    /// `SuggestMilestonePhotos`' answer, as server ids, best first. Offered, never attached until tapped.
    @State private var suggestedPhotoRemoteIds: [Int] = []
    @FocusState private var isTextFocused: Bool

    /// Every photo in the store, so an attachment made elsewhere can be matched back to a local record — see `milestonePhotoChoices`.
    @Query private var allPhotos: [Photo]

    init(milestone: Milestone) {
        self.milestone = milestone
        _descriptionText = State(initialValue: milestone.descriptionText)
        _category = State(initialValue: milestone.category)
        _context = State(initialValue: milestone.context)
        _date = State(initialValue: milestone.date.displayDay())
        let entry = RecordWhenEntry(recordTime: milestone.recordTime, date: milestone.date)
        _recordWhen = State(initialValue: entry)
        initialRecordWhen = entry
    }

    private var approximate: Bool { RecordTimeSettings.shared.approximateDates }

    private var birthday: Date? {
        milestone.person?.isPregnancy == true ? nil : milestone.person?.birthday
    }

    /// An interview answer, edited without its category or date.
    private var isAnswer: Bool { milestone.category == .interview }

    private var isValid: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var photoChoices: [Photo] {
        milestonePhotoChoices(for: milestone, person: milestone.person, allPhotos: allPhotos)
    }

    /// The choices the milestone has attached right now.
    private var attachedChoices: [Photo] {
        let attached = Set(milestone.photoRemoteIds)
        return photoChoices.filter { photo in photo.serverId.map { attached.contains($0) } ?? false }
    }

    /// What the milestone had attached when the editor opened. Not suggested again: they are in the picker already.
    private var originallyAttached: Set<Int> { Set(milestone.photoRemoteIds) }

    private var suggestedPhotos: [Photo] {
        MilestonePhotoSuggestions.offered(suggestedPhotoRemoteIds, choices: photoChoices, alreadyAttached: originallyAttached)
    }

    private var lookupKey: String {
        MilestoneSuggestionLookup.key(
            personRemoteId: milestone.person?.remoteId,
            text: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            day: date.localRecordDay(),
            isConnected: network.isConnected
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if isAnswer {
                    // An interview answer: the question and the date belong to the interview, so only the answer is edited here.
                    Section {
                        TextField(Copy.interview.ask.answerPlaceholder, text: $descriptionText, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($isTextFocused)
                    } header: {
                        Text(milestone.context)
                            .textCase(nil)
                    } footer: {
                        Text(Copy.interview.answerDateHint)
                    }
                } else {
                    Section {
                        Picker(Copy.milestone.category, selection: $category) {
                            ForEach(MilestoneCategory.pickable, id: \.self) { option in
                                Text(option.label)
                            }
                        }
                    }

                    MilestoneTextSections(category: category, descriptionText: $descriptionText, context: $context, isFocused: $isTextFocused)

                    if approximate {
                        Section {
                            RecordWhenControl(entry: $recordWhen, isMoment: true, birthday: birthday)
                        }
                    } else if milestone.hasExactDate {
                        Section {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                        }
                    } else {
                        // A picker would flatten "at age 4" to one day; the server refuses that from a legacy date edit.
                        Section {
                            LabeledContent("Date", value: milestone.recordTime?.label ?? "")
                        } footer: {
                            Text(Copy.milestone.approximateDateHint)
                        }
                    }
                }

                MilestonePhotoSections(category: category, newPhotos: $newPhotos, isReadingPhotos: $isReadingPhotos, suggestedPhotos: suggestedPhotos, selectedPhotoIds: $selectedPhotoIds)

                MilestonePhotosSection(
                    photos: photoChoices,
                    emptyDescription: "Tag \(milestone.person?.name ?? "this person") in a photo to attach it to a moment.",
                    selection: $selectedPhotoIds
                )
            }
            // The `@Query` this needs isn't available in `init`, and re-seeding on the way back from the picker would undo the user's edits.
            .task {
                guard !didSeedSelection else { return }
                didSeedSelection = true
                selectedPhotoIds = Set(attachedChoices.map(\.id))
            }
            .task(id: lookupKey) {
                await lookUpSuggestions()
            }
            .task {
                await RecordTimeSettings.shared.refresh()
            }
            .navigationTitle(isAnswer ? Copy.interview.editAnswer : "Edit Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.milestone.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.milestone.save) {
                        save()
                    }
                    .disabled(!isValid || isReadingPhotos)
                }
            }
        }
    }

    /// Photos of the person from around the milestone's date. Waits for the inputs to settle; a newer key cancels this one. Offline, or on any failure, the row empties and the selection is left exactly as it was.
    private func lookUpSuggestions() async {
        guard await MilestoneSuggestionLookup.settle() else { return }

        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard network.isConnected,
              let personId = milestone.person?.serverId,
              text.count >= 3 else {
            suggestedPhotoRemoteIds = []
            return
        }
        let ids = await AnalysisService.shared.suggestMilestonePhotos(
            personId: personId,
            description: text,
            date: date.localRecordDay(),
            excludeIds: Array(originallyAttached)
        )
        if !Task.isCancelled {
            suggestedPhotoRemoteIds = ids
        }
    }

    private func save() {
        guard !isReadingPhotos else { return }
        var recordTime: RecordTime?
        if approximate && !isAnswer && recordWhen != initialRecordWhen {
            var entry = recordWhen
            entry.anchorPersonId = milestone.person?.serverId ?? 0
            if let problem = entry.problem(isMoment: true, birthday: birthday) {
                errorPresenter.report(message: problem, title: "Couldn't Save Moment")
                return
            }
            recordTime = entry.recordTime(isMoment: true, birthday: birthday)
        }
        milestone.category = category
        milestone.setEntry(descriptionText, context: context)
        if let recordTime {
            milestone.recordTime = recordTime
            milestone.date = recordTime.isExactDay ? (DaySummaries.date(of: recordTime.from) ?? milestone.date) : RecordWhenEntry.sortDate(recordTime)
        } else if !isAnswer && !approximate && milestone.hasExactDate {
            milestone.date = date.localRecordDay()
        }
        let sentRecordTime = recordTime

        // `photoIds` is the complete set the milestone should end up with, so an empty selection detaches everything — safe only once the seed has run, since before that an empty selection means "not loaded yet".
        let chosen = didSeedSelection ? photoChoices.filter { selectedPhotoIds.contains($0.id) } : nil
        let attached = attachedChoices
        let picked = newPhotos

        dismiss()

        Task { [milestone, modelContext] in
            do {
                var photos = chosen
                if let artist = milestone.person, !picked.isEmpty {
                    // New pieces join the selection — or, without a seeded one, what the milestone already has.
                    photos = (chosen ?? attached)
                        + (try await MilestonePhotoUploads.queue(picked, artist: artist, context: modelContext, syncService: syncService))
                }
                try await syncService.updateMilestone(milestone, photos: photos, recordTime: sentRecordTime)
            } catch {
                errorPresenter.report(error, title: "Couldn't Save Moment")
            }
        }
    }
}

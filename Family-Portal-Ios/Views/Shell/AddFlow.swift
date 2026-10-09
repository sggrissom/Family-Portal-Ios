import Photos
import PhotosUI
import SwiftData
import SwiftUI

/// What the add sheet leads to once a choice is made.
enum AddForm: Identifiable, Equatable {
    case measurement(personId: UUID?)
    case milestone(personId: UUID?)
    case person

    var id: String {
        switch self {
        case .measurement(let id): return "measurement-\(id?.uuidString ?? "")"
        case .milestone(let id): return "milestone-\(id?.uuidString ?? "")"
        case .person: return "person"
        }
    }
}

/// The one add sheet, presented from the shell like `ErrorPresenter`'s alert, so every **+** in the app opens the same thing and words it the same way.
/// A person is preselected only from the screen underneath — a person page passes itself — or from the remembered choice, and it is always a visible chip that can be cleared.
/// Each form is a sheet over whatever screen was showing, so its **Done** returns there.
@MainActor
@Observable
final class AddFlow {
    var isSheetPresented = false
    /// The person the sheet was opened for, if the screen underneath named one. Only this reaches the photo form's **Who's in these?** — a remembered person never does.
    private(set) var contextPersonId: UUID?

    /// The form showing after the sheet closed.
    var form: AddForm?
    /// The photo batch form, over an import already under way.
    var photoBatch: PhotoBatch?
    /// Waiting for the sheet to finish dismissing: SwiftUI will not present a second sheet while the first is still animating away.
    private var pendingForm: AddForm?
    private var pendingPhotos = false
    private var pendingEvent: OpenEventDTO?

    var isPickingPhotos = false
    let importer = PhotoImporter()

    /// Pushes the chosen event onto the current tab once the sheet is gone. Set by the shell, which owns navigation.
    var openEvent: ((OpenEventDTO) -> Void)?

    func present(for personId: UUID? = nil) {
        contextPersonId = personId
        isSheetPresented = true
    }

    /// Closes the sheet, then opens the chosen form from `sheetDidDismiss`.
    func choose(_ form: AddForm) {
        pendingForm = form
        isSheetPresented = false
    }

    /// Opens a form directly, with no sheet in front — a roster row's long press already said what and for whom.
    func open(_ form: AddForm) {
        self.form = form
    }

    func choosePhotos() {
        pendingPhotos = true
        isSheetPresented = false
    }

    func chooseResult(for event: OpenEventDTO) {
        pendingEvent = event
        isSheetPresented = false
    }

    func sheetDidDismiss() {
        if let pendingForm {
            form = pendingForm
            self.pendingForm = nil
        } else if pendingPhotos {
            isPickingPhotos = true
            pendingPhotos = false
        } else if let pendingEvent {
            openEvent?(pendingEvent)
            self.pendingEvent = nil
        }
    }

    /// Starts the import at once and opens the batch form over it. Photos are tagged with nobody at import; the form asks, preselecting only the person whose page the batch came from.
    func startBatch(_ items: [PhotosPickerItem], context: ModelContext, syncService: SyncService?, errorPresenter: ErrorPresenter?) {
        let entryIds = importer.importPicked(items, into: context, syncService: syncService, errorPresenter: errorPresenter)
        guard !entryIds.isEmpty else { return }
        photoBatch = PhotoBatch(
            entryIds: entryIds,
            preselectedPersonIds: contextPersonId.map { [$0] } ?? []
        )
    }
}

extension View {
    /// Everything the add flow presents: the sheet, the forms it leads to, the photo picker and the batch form. Applied once, at the shell.
    func addFlowPresentation(_ flow: AddFlow) -> some View {
        modifier(AddFlowPresentation(flow: flow))
    }
}

private struct AddFlowPresentation: ViewModifier {
    @Bindable var flow: AddFlow

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(ErrorPresenter.self) private var errorPresenter

    @State private var pickedItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $flow.isSheetPresented, onDismiss: flow.sheetDidDismiss) {
                AddSheetView(flow: flow)
            }
            .sheet(item: $flow.form) { form in
                switch form {
                case .measurement(let personId):
                    AddMeasurementView(personId: personId)
                case .milestone(let personId):
                    AddMilestoneView(personId: personId)
                case .person:
                    AddPersonView()
                }
            }
            .sheet(item: $flow.photoBatch) { batch in
                PhotoBatchFormView(batch: batch, importer: flow.importer)
            }
            .photosPicker(
                isPresented: $flow.isPickingPhotos,
                selection: $pickedItems,
                maxSelectionCount: nil,
                // `.ordered` numbers the picks and delivers them in the order the user made them, not library order.
                selectionBehavior: .ordered,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: pickedItems) { _, newItems in
                // Clearing the binding re-enters this with an empty array, which `startBatch` ignores. Without it, picking the same photo twice in a row never fires.
                pickedItems = []
                flow.startBatch(newItems, context: modelContext, syncService: syncService, errorPresenter: errorPresenter)
            }
    }
}

/// **Who is this for?**, then Photos · Measurement · Milestone, then up to two **Result — {event}** rows for events open for results. Backfilling older events goes through Activities.
struct AddSheetView: View {
    let flow: AddFlow

    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var activityService
    @Environment(AuthService.self) private var authService

    @State private var personId: UUID?
    @State private var openEvents = ActivityScreenState<ListOpenEventsResponseDTO>()
    @State private var didSeed = false

    private let defaults = QuickAddDefaults()

    /// Everyone in a family the account can add to; a view-only family's people are never offered.
    private var writablePeople: [Person] {
        people.filter { authService.access.canContribute(to: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !writablePeople.isEmpty {
                    Section(Copy.addSheet.whoFor) {
                        PersonChips(selection: $personId, contributableOnly: true)
                    }
                }

                Section {
                    Button {
                        flow.choosePhotos()
                    } label: {
                        Label(Copy.addSheet.photos, systemImage: "photo.on.rectangle")
                    }
                    Button {
                        remember()
                        flow.choose(.measurement(personId: personId))
                    } label: {
                        Label(Copy.addSheet.measurement, systemImage: MeasurementType.height.icon)
                    }
                    .disabled(writablePeople.isEmpty)
                    Button {
                        remember()
                        flow.choose(.milestone(personId: personId))
                    } label: {
                        Label(Copy.addSheet.milestone, systemImage: MilestoneCategory.first.icon)
                    }
                    .disabled(writablePeople.isEmpty)
                }

                if let events = openEvents.value?.events, !events.isEmpty {
                    Section {
                        ForEach(events.prefix(2)) { open in
                            Button {
                                flow.chooseResult(for: open)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("\(Copy.result) — \(open.event.name)", systemImage: "trophy")
                                    if let day = ActivityDateText.range(from: open.event.startDate, to: open.event.endDate) {
                                        Text(day)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Copy.addSheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.addSheet.close) { dismiss() }
                }
            }
            .onAppear(perform: seed)
            .task {
                await openEvents.load(activityService.openEvents(today: WhenEntry.localDateString(Date())))
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The screen underneath first, then the remembered person — as a chip the user can see and clear.
    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        personId = flow.contextPersonId ?? QuickAddDefaults.person(
            in: writablePeople,
            remembered: defaults.rememberedPersonId,
            relations: relations.map(\.edge)
        )?.id
    }

    /// Written back as the remembered person, the way the web writes `last-person-id`.
    private func remember() {
        if let personId {
            defaults.rememberPerson(personId)
        }
    }
}

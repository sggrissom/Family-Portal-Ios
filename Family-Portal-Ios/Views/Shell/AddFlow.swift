import OSLog
import Photos
import PhotosUI
import SwiftData
import SwiftUI

/// What the add sheet leads to once a choice is made.
enum AddForm: Identifiable, Equatable {
    case measurement(personId: UUID?)
    case milestone(personId: UUID?)
    /// A moment with its category already set to quote: Siri's and the controls' "Add quote".
    case quote(personId: UUID?)
    /// An artwork moment with the document camera already open.
    case scannedArtwork(personId: UUID?)
    case person

    var id: String {
        switch self {
        case .measurement(let id): return "measurement-\(id?.uuidString ?? "")"
        case .milestone(let id): return "milestone-\(id?.uuidString ?? "")"
        case .quote(let id): return "quote-\(id?.uuidString ?? "")"
        case .scannedArtwork(let id): return "scan-\(id?.uuidString ?? "")"
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
    private var pendingRoute: AppRoute?

    var isPickingPhotos = false
    let importer = PhotoImporter()

    /// Whether the picker offers videos: only when the server says video is on for the account's family.
    var acceptsVideo: Bool { importer.videoSupport?.enabled == true }

    /// Pushes a chosen screen — an event's results, an interview — onto the current tab once the sheet is gone. Set by the shell, which owns navigation.
    var openRoute: ((AppRoute) -> Void)?

    /// Who the screen on top is about, set by `addsFor(_:)` while it shows: a person page, a moment, a photo of one person. The tab bar's **+** opens for them, as the web's Add does from those pages.
    private(set) var pagePersonId: UUID?
    private var pageToken: UUID?

    func present(for personId: UUID? = nil) {
        contextPersonId = personId ?? pagePersonId
        isSheetPresented = true
    }

    func showing(_ personId: UUID?, token: UUID) {
        pagePersonId = personId
        pageToken = token
    }

    /// Only the screen that set the person clears it, so a screen appearing before the last one's disappearance doesn't lose its own.
    func leaving(token: UUID) {
        guard pageToken == token else { return }
        pagePersonId = nil
        pageToken = nil
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

    /// Opens the photo picker directly, with no sheet in front — an App Intent or quick action already said what.
    func pickPhotos() {
        isPickingPhotos = true
    }

    func choosePhotos() {
        pendingPhotos = true
        isSheetPresented = false
    }

    func chooseResult(for event: OpenEventDTO) {
        chooseRoute(.event(id: event.event.id, name: event.event.name))
    }

    func chooseRoute(_ route: AppRoute) {
        pendingRoute = route
        isSheetPresented = false
    }

    func sheetDidDismiss() {
        if let pendingForm {
            form = pendingForm
            self.pendingForm = nil
        } else if pendingPhotos {
            isPickingPhotos = true
            pendingPhotos = false
        } else if let pendingRoute {
            openRoute?(pendingRoute)
            self.pendingRoute = nil
        }
    }

    /// Asked each time the sheet opens, and only online: video is an admin's switch per family, so a remembered answer could be wrong either way, and a video can't upload offline anyway.
    func refreshVideoSupport(isConnected: Bool, apiClient: APIClient = .shared) async {
        guard isConnected else {
            importer.videoSupport = nil
            return
        }
        do {
            importer.videoSupport = try await apiClient.callRPC(.getVideoSupport, payload: GetVideoSupportRequestDTO())
        } catch {
            AppLog.ui.error("Couldn't ask for video support: \(String(describing: error), privacy: .public)")
            importer.videoSupport = nil
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
                case .quote(let personId):
                    AddMilestoneView(personId: personId, category: .quote)
                case .scannedArtwork(let personId):
                    AddMilestoneView(personId: personId, category: .artwork, startsScanning: true)
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
                matching: flow.acceptsVideo ? .any(of: [.images, .videos]) : .images,
                photoLibrary: .shared()
            )
            .onChange(of: pickedItems) { _, newItems in
                // Clearing the binding re-enters this with an empty array, which `startBatch` ignores. Without it, picking the same photo twice in a row never fires.
                pickedItems = []
                flow.startBatch(newItems, context: modelContext, syncService: syncService, errorPresenter: errorPresenter)
            }
    }
}

/// **Who is this for?**, then Photos · Measurement · Milestone · Interview, then up to two **Result — {event}** rows for events open for results. Backfilling older events goes through Activities.
struct AddSheetView: View {
    let flow: AddFlow

    @Query private var people: [Person]
    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var activityService
    @Environment(AuthService.self) private var authService
    @Environment(NetworkMonitor.self) private var network

    @State private var personId: UUID?
    @State private var openEvents = ActivityScreenState<ListOpenEventsResponseDTO>()
    @State private var didSeed = false

    private let defaults = QuickAddDefaults()

    /// Everyone in a family the account can add to; a view-only family's people are never offered.
    private var writablePeople: [Person] {
        people.filter { authService.access.canContribute(to: $0) }
    }

    private var selectedPerson: Person? {
        writablePeople.first { $0.id == personId }
    }

    var body: some View {
        NavigationStack {
            List {
                if !writablePeople.isEmpty {
                    Section(Copy.addSheet.whoFor) {
                        PersonChips(selection: $personId, contributableOnly: true, includeUnborn: true)
                    }
                }

                Section {
                    Button {
                        flow.choosePhotos()
                    } label: {
                        Label(flow.acceptsVideo ? Copy.addSheet.photosAndVideos : Copy.addSheet.photos, systemImage: "photo.on.rectangle")
                    }
                    Button {
                        remember()
                        // An expected baby has nothing to measure yet; the form falls back to its own default.
                        flow.choose(.measurement(personId: writablePeople.first { $0.id == personId && !$0.isPregnancy }?.id))
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
                    if DocumentScannerView.isAvailable {
                        Button {
                            remember()
                            flow.choose(.scannedArtwork(personId: personId))
                        } label: {
                            Label(Copy.addSheet.scanArtwork, systemImage: "doc.viewfinder")
                        }
                        .disabled(writablePeople.isEmpty)
                    }
                    if selectedPerson?.isPregnancy != true {
                        Button {
                            flow.chooseRoute(selectedPerson?.serverId.map { AppRoute.interviewSetup(personId: $0) } ?? .interviews)
                        } label: {
                            Label(Copy.addSheet.interview, systemImage: "mic")
                        }
                        .disabled(writablePeople.isEmpty)
                    }
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
            .task {
                await flow.refreshVideoSupport(isConnected: network.isConnected)
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Only the person whose page is underneath, as a chip the user can see and clear: whoever was last used is left to the measurement and moment forms, so a photo batch doesn't arrive tagged with them.
    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        personId = writablePeople.first { $0.id == flow.contextPersonId }?.id
    }

    /// Written back as the remembered person, the way the web writes `last-person-id`.
    private func remember() {
        if let personId {
            defaults.rememberPerson(personId)
        }
    }
}

private struct AddsFor: ViewModifier {
    let personId: UUID?
    @Environment(AddFlow.self) private var addFlow
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { addFlow.showing(personId, token: token) }
            .onChange(of: personId) { _, id in addFlow.showing(id, token: token) }
            .onDisappear { addFlow.leaving(token: token) }
    }
}

extension View {
    /// Names the person this screen is about, so the add sheet opens with them chosen while it shows.
    func addsFor(_ personId: UUID?) -> some View {
        modifier(AddsFor(personId: personId))
    }
}

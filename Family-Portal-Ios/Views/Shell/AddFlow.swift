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
/// A person is preselected only from the screen underneath — a person page passes itself — and never inherited silently.
@MainActor
@Observable
final class AddFlow {
    var isSheetPresented = false
    /// The person the sheet was opened for, if the screen underneath named one.
    private(set) var contextPersonId: UUID?

    /// The form showing after the sheet closed.
    var form: AddForm?
    /// Waiting for the sheet to finish dismissing: SwiftUI will not present a second sheet while the first is still animating away.
    private var pendingForm: AddForm?
    private var pendingPhotos = false

    var isPickingPhotos = false
    let importer = PhotoImporter()

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

    func sheetDidDismiss() {
        if let pendingForm {
            form = pendingForm
            self.pendingForm = nil
        } else if pendingPhotos {
            isPickingPhotos = true
            pendingPhotos = false
        }
    }
}

extension View {
    /// Everything the add flow presents: the sheet, the forms it leads to, and the photo picker. Applied once, at the shell.
    func addFlowPresentation(_ flow: AddFlow) -> some View {
        modifier(AddFlowPresentation(flow: flow))
    }
}

private struct AddFlowPresentation: ViewModifier {
    @Bindable var flow: AddFlow

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    @State private var pickedItems: [PhotosPickerItem] = []

    /// Photos picked from a person's own **+** are tagged with them; from anywhere else, with nobody.
    private var contextPerson: Person? {
        guard let personId = flow.contextPersonId else { return nil }
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate<Person> { person in
            person.id == personId
        })
        return try? modelContext.fetch(descriptor).first
    }

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
            .photosPicker(
                isPresented: $flow.isPickingPhotos,
                selection: $pickedItems,
                maxSelectionCount: nil,
                // `.ordered` numbers the picks and delivers them in the order the user made them, not library order.
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: pickedItems) { _, newItems in
                // Clearing the binding re-enters this with an empty array, which the importer absorbs. Without it, picking the same photo twice in a row never fires.
                pickedItems = []
                flow.importer.importPicked(
                    newItems,
                    into: modelContext,
                    syncService: syncService,
                    errorPresenter: errorPresenter,
                    taggingTo: contextPerson
                )
            }
    }
}

/// Photos · Measurement · Milestone. Measurement and Milestone are *about* somebody, so they are disabled on an empty roster rather than opening a form that could never save.
struct AddSheetView: View {
    let flow: AddFlow

    @Query private var people: [Person]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    flow.choosePhotos()
                } label: {
                    Label(Copy.addSheet.photos, systemImage: "photo.on.rectangle")
                }
                Button {
                    flow.choose(.measurement(personId: flow.contextPersonId))
                } label: {
                    Label(Copy.addSheet.measurement, systemImage: MeasurementType.height.icon)
                }
                .disabled(people.isEmpty)
                Button {
                    flow.choose(.milestone(personId: flow.contextPersonId))
                } label: {
                    Label(Copy.addSheet.milestone, systemImage: MilestoneCategory.first.icon)
                }
                .disabled(people.isEmpty)
            }
            .navigationTitle(Copy.addSheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.addSheet.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

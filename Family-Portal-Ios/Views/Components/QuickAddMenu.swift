import PhotosUI
import SwiftUI
import SwiftData

/// What the `+` on a tab root can open.
enum QuickAddKind: String, Identifiable, CaseIterable {
    case milestone
    case measurement
    case photos
    case person

    var id: String { rawValue }

    var label: String {
        switch self {
        case .milestone: "Milestone"
        case .measurement: "Measurement"
        case .photos: "Photos"
        case .person: "Person"
        }
    }

    var icon: String {
        switch self {
        // The milestone and measurement glyphs are the ones `RecordStyle` already draws those records with, so the menu and the row it produces agree.
        case .milestone: MilestoneCategory.first.icon
        case .measurement: MeasurementType.height.icon
        case .photos: "photo.on.rectangle"
        case .person: "person.badge.plus"
        }
    }

    /// A milestone and a measurement are *about* somebody: an empty roster has nothing to hang one on, so those two are offered but disabled rather than opening a sheet that cannot save.
    var needsSomeone: Bool {
        switch self {
        case .milestone, .measurement: true
        case .photos, .person: false
        }
    }
}

/// The `+` the Family and Timeline tabs share.
struct QuickAddMenu: View {
    let hasPeople: Bool
    let onSelect: (QuickAddKind) -> Void

    var body: some View {
        Menu {
            ForEach(QuickAddKind.allCases) { kind in
                Button {
                    onSelect(kind)
                } label: {
                    Label(kind.label, systemImage: kind.icon)
                }
                .disabled(kind.needsSomeone && !hasPeople)
            }
        } label: {
            Image(systemName: "plus")
        }
        // A bare glyph has no accessible name; VoiceOver would announce "plus".
        .accessibilityLabel("Add")
    }
}

extension View {
    /// Puts the quick-add `+` in this screen's toolbar, along with everything the four choices need: the three sheets, the photo picker, and the import's progress bar.
    /// One modifier rather than a copy per tab, so Family and Timeline cannot offer different things or word them differently.
    func quickAdd(people: [Person]) -> some View {
        modifier(QuickAddModifier(people: people))
    }
}

private struct QuickAddModifier: ViewModifier {
    let people: [Person]

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    @State private var sheet: QuickAddKind?
    @State private var isPickingPhotos = false
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var importer = PhotoImporter()

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    QuickAddMenu(hasPeople: !people.isEmpty) { kind in
                        // Photos is a picker rather than a sheet, so it is the one choice that does not go through `sheet`.
                        if kind == .photos {
                            isPickingPhotos = true
                        } else {
                            sheet = kind
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let progress = importer.progress {
                    PhotoImportProgressBar(progress: progress)
                }
            }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .milestone:
                    // No person: the sheet asks, which is what phase 1 was for.
                    AddMilestoneView()
                case .measurement:
                    AddMeasurementView()
                case .person:
                    AddPersonView()
                case .photos:
                    // Unreachable — `.photos` sets `isPickingPhotos` and never lands here.
                    EmptyView()
                }
            }
            .photosPicker(
                isPresented: $isPickingPhotos,
                selection: $pickedItems,
                maxSelectionCount: nil,
                // `.ordered` numbers the picks and delivers them in the order the user made them, not library order.
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: pickedItems) { _, newItems in
                // Clearing the binding re-enters this with an empty array, which the importer absorbs. Without it, picking the same photo twice in a row never fires.
                pickedItems = []
                importer.importPicked(
                    newItems,
                    into: modelContext,
                    syncService: syncService,
                    errorPresenter: errorPresenter
                )
            }
    }
}

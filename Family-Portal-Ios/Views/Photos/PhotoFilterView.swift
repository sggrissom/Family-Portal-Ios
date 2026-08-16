import SwiftUI
import SwiftData

/// The gallery's filter panel: people, tags and a date window, matching the
/// web's (`frontend/pages/photos/family-photos.tsx`).
///
/// Every change applies immediately to the grid behind it — the same
/// immediate-apply choice `TagPickerView` and "Manage Tagged People" already
/// make — so the sheet has Done rather than Apply, and dismissing never discards
/// anything.
///
/// People and tags come from the local store, not from `ListPeople`/`ListTags` as
/// the web fetches them: the gallery it filters is local too, so a filter that
/// needed the network would be unusable in exactly the situation this app is
/// built for.
struct PhotoFilterView: View {
    @Binding var filter: PhotoFilter

    @Query(sort: \Person.name) private var people: [Person]
    @Query private var tags: [FamilyTag]
    @Environment(\.dismiss) private var dismiss

    /// `ListTags` sorts case-insensitively by name; the same order here keeps the
    /// two clients' panels reading alike.
    private var sortedTags: [FamilyTag] {
        tags.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        List {
            peopleSection
            tagsSection
            dateSection

            if filter.hasPanelFilters {
                Section {
                    Button("Clear All Filters", role: .destructive) {
                        var updated = filter
                        updated.clearPanelFilters()
                        filter = updated
                    }
                }
            }
        }
        .navigationTitle("Filter Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        Section("People") {
            if people.isEmpty {
                Text("No people yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(people) { person in
                    let isSelected = filter.personLocalIds.contains(person.id)
                    Button {
                        var updated = filter
                        updated.personLocalIds = toggling(person.id, in: updated.personLocalIds)
                        filter = updated
                    } label: {
                        HStack {
                            Text(person.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section("Tags") {
            if sortedTags.isEmpty {
                Text("This family hasn't created any tags yet. Tags are created on the web.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedTags) { tag in
                    // A tag the pull stored without a usable id can't match
                    // anything, since `Photo.tagRemoteIds` holds server ids.
                    let remoteId = tag.remoteId.flatMap(Int.init)
                    let isSelected = remoteId.map { filter.tagRemoteIds.contains($0) } ?? false

                    Button {
                        if let remoteId {
                            var updated = filter
                            updated.tagRemoteIds = toggling(remoteId, in: updated.tagRemoteIds)
                            filter = updated
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(TagColor.color(forHex: tag.colorHex))
                                .frame(width: 12, height: 12)
                            Text(tag.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(remoteId == nil)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        Section("Date") {
            Toggle("Earliest Date", isOn: bound(\.dateFrom, default: Self.defaultFrom))
            if filter.dateFrom != nil {
                DatePicker(
                    "From",
                    selection: unwrapped(\.dateFrom, default: Self.defaultFrom),
                    displayedComponents: .date
                )
            }

            Toggle("Latest Date", isOn: bound(\.dateTo, default: Date()))
            if filter.dateTo != nil {
                DatePicker(
                    "To",
                    selection: unwrapped(\.dateTo, default: Date()),
                    displayedComponents: .date
                )
            }
        }
    }

    /// The two halves of the window are independently optional — "everything
    /// since June" is as ordinary a request as a closed range — so each end is a
    /// switch over a `Date?` rather than a picker that is always showing some
    /// date the user never chose.
    private func bound(_ keyPath: WritableKeyPath<PhotoFilter, Date?>, default fallback: @autoclosure @escaping () -> Date) -> Binding<Bool> {
        Binding(
            get: { filter[keyPath: keyPath] != nil },
            set: { isOn in
                var updated = filter
                updated[keyPath: keyPath] = isOn ? (updated[keyPath: keyPath] ?? fallback()) : nil
                filter = updated
            }
        )
    }

    private func unwrapped(_ keyPath: WritableKeyPath<PhotoFilter, Date?>, default fallback: @autoclosure @escaping () -> Date) -> Binding<Date> {
        Binding(
            get: { filter[keyPath: keyPath] ?? fallback() },
            set: { newValue in
                var updated = filter
                updated[keyPath: keyPath] = newValue
                filter = updated
            }
        )
    }

    /// A month back, so switching "From" on lands on a window that holds
    /// something. Today would show an empty grid and read as a broken filter.
    private static var defaultFrom: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }

    private func toggling<T: Hashable>(_ value: T, in set: Set<T>) -> Set<T> {
        var result = set
        if result.contains(value) {
            result.remove(value)
        } else {
            result.insert(value)
        }
        return result
    }
}

import SwiftUI
import SwiftData

/// `SyncService.updateMilestone` and the backend's `UpdateMilestone` proc were
/// both fully implemented and unreachable: a typo in a milestone could only be
/// fixed on the website (milestones/edit-milestone.tsx).
struct EditMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    let milestone: Milestone

    @State private var descriptionText: String
    @State private var category: MilestoneCategory
    @State private var date: Date

    init(milestone: Milestone) {
        self.milestone = milestone
        _descriptionText = State(initialValue: milestone.descriptionText)
        _category = State(initialValue: milestone.category)
        _date = State(initialValue: milestone.date)
    }

    private var isValid: Bool {
        !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(MilestoneCategory.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized)
                        }
                    }
                }

                Section {
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Edit Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        milestone.descriptionText = descriptionText.trimmingCharacters(in: .whitespaces)
        milestone.category = category
        milestone.date = date

        // The write is already local and the queue guarantees delivery, so the
        // sheet doesn't wait on the network to close.
        dismiss()

        Task { [milestone] in
            do {
                try await syncService?.updateMilestone(milestone)
            } catch {
                errorPresenter?.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}

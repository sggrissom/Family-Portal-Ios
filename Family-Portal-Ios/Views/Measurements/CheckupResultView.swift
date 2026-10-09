import OSLog
import SwiftUI
import SwiftData

/// Where a checkup lands: each value it saved, with its percentile and the family comparison, then the Same age strip, each value marked **Saved** once the server has it and **Waiting to sync** until then.
/// **Add another measurement** and **Done** are pinned below the scroll rather than at the end of it, so entering several checkups in a row never means scrolling past the comparisons to reach them.
/// The checkup is queued as one operation, so a failed enqueue marks every value not saved and **Retry** queues them again together. A queued value that is later discarded already reaches the user through `discardedChangeWarning`, so there is no failure path here for that.
struct CheckupResultView: View {
    let onAddAnother: () -> Void
    let onDone: () -> Void

    @State private var result: CheckupResult
    @Query private var records: [GrowthData]
    @Environment(SyncService.self) private var syncService
    @State private var isRetrying = false

    init(result: CheckupResult, onAddAnother: @escaping () -> Void, onDone: @escaping () -> Void) {
        _result = State(initialValue: result)
        self.onAddAnother = onAddAnother
        self.onDone = onDone
        let ids = result.recordIds
        _records = Query(filter: #Predicate<GrowthData> { record in
            ids.contains(record.id)
        })
    }

    /// In the order the checkup entered them — height first.
    private var ordered: [GrowthData] {
        result.recordIds.compactMap { id in records.first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(ordered) { record in
                    VStack(alignment: .leading, spacing: 12) {
                        status(for: record)
                        MeasurementInsightsView(measurement: record, showsSameAge: false)
                    }
                }

                // One person on one day, so one strip for the whole checkup rather than one per value.
                if let first = ordered.first {
                    PersonSameAgeStrip(person: first.person, date: first.date)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actions
        }
        .navigationTitle(Copy.home.checkupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }

    /// One row, so the bar takes as little of the screen as it can.
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                onDone()
            } label: {
                Text(Copy.photos.done)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)

            Button {
                onAddAnother()
            } label: {
                Text("Add another measurement")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func status(for record: GrowthData) -> some View {
        if result.failedIds.contains(record.id) {
            HStack {
                Label("Not saved", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") { retry() }
                    .disabled(isRetrying)
            }
            .font(.subheadline)
        } else if record.remoteId != nil {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else {
            Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func retry() {
        let failed = ordered.filter { result.failedIds.contains($0.id) }
        guard let person = failed.first?.person else { return }
        isRetrying = true
        Task {
            defer { isRetrying = false }
            do {
                try await syncService.addCheckup(failed, for: person)
                result.failedIds.subtract(failed.map(\.id))
            } catch {
                AppLog.ui.error("Retrying a checkup failed again: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

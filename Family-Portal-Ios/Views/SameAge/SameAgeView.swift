import SwiftUI

/// **At {age}** — everyone in the family at one age, from `GetSameAge`. Younger and Older step along the `AgeSteps` grid; the age can also be entered directly.
/// Opened with a person and an age from a record, a person page or a link. Opened with neither, the server starts from the youngest own child's current age.
struct SameAgeView: View {
    /// Nil means the anchor's current age.
    @State private var ageMonths: Int?
    @State private var fromRemoteId: Int
    @State private var loader = SameAgeLoader()
    @State private var isPickingAge = false

    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    init(ageMonths: Int? = nil, fromRemoteId: Int = 0) {
        _ageMonths = State(initialValue: ageMonths)
        _fromRemoteId = State(initialValue: fromRemoteId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch loader.state {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .offline:
                    ContentUnavailableView(
                        "You're offline",
                        systemImage: "wifi.slash",
                        description: Text("Same age needs a connection the first time it opens an age.")
                    )
                case .failed(let message):
                    ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(message))
                case .loaded(let response):
                    loaded(response)
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(fromRemoteId)-\(ageMonths.map(String.init) ?? "now")") {
            await loader.load(ageMonths: ageMonths, fromPersonId: fromRemoteId, isConnected: network?.isConnected ?? true)
        }
        .refreshable {
            SameAgeCache.shared.removeAll()
            await loader.load(ageMonths: ageMonths, fromPersonId: fromRemoteId, isConnected: network?.isConnected ?? true)
        }
        .sheet(isPresented: $isPickingAge) {
            if let response = loader.response {
                AgePickerSheet(initial: response.ageMonths, maxMonths: response.maxAgeMonths) { picked in
                    ageMonths = picked
                }
            }
        }
    }

    private var title: String {
        guard let response = loader.response else { return Copy.sameAge.title }
        return "\(Copy.sameAge.at) \(AgeSteps.ageTitle(response.ageMonths))"
    }

    @ViewBuilder
    private func loaded(_ response: GetSameAgeResponseDTO) -> some View {
        HStack {
            Button {
                step(to: AgeSteps.prevAge(response.ageMonths), from: response)
            } label: {
                Label(Copy.sameAge.younger, systemImage: "chevron.left")
            }
            .disabled(response.ageMonths <= 0)

            Spacer()

            Button {
                isPickingAge = true
            } label: {
                Text(AgeSteps.ageTitle(response.ageMonths))
                    .font(.headline)
            }
            .accessibilityHint("Choose an age")

            Spacer()

            Button {
                step(to: AgeSteps.nextAge(response.ageMonths, maxMonths: response.maxAgeMonths), from: response)
            } label: {
                Label(Copy.sameAge.older, systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .disabled(response.ageMonths >= response.maxAgeMonths)
        }
        .buttonStyle(.bordered)

        if response.rows.isEmpty {
            Text(Copy.sameAge.empty)
                .foregroundStyle(.secondary)
        } else {
            SameAgeMontage(rows: response.rows)
                .id(response.ageMonths)
            SameAgeRows(rows: response.rows, ageMonths: response.ageMonths)
        }
    }

    /// Pins the anchor the server settled on, so stepping stays about the same person.
    private func step(to age: Int, from response: GetSameAgeResponseDTO) {
        fromRemoteId = response.fromPersonId
        ageMonths = age
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// Years and months, snapped onto the age grid on the way out.
private struct AgePickerSheet: View {
    let maxMonths: Int
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var years: Int
    @State private var months: Int

    init(initial: Int, maxMonths: Int, onPick: @escaping (Int) -> Void) {
        self.maxMonths = maxMonths
        self.onPick = onPick
        _years = State(initialValue: initial / 12)
        _months = State(initialValue: initial % 12)
    }

    var body: some View {
        NavigationStack {
            HStack {
                Picker("Years", selection: $years) {
                    ForEach(0...max(0, maxMonths / 12), id: \.self) { Text($0 == 1 ? "1 year" : "\($0) years").tag($0) }
                }
                Picker("Months", selection: $months) {
                    ForEach(0...11, id: \.self) { Text($0 == 1 ? "1 month" : "\($0) months").tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .padding()
            .navigationTitle(Copy.sameAge.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let raw = min(years * 12 + months, maxMonths)
                        let step = AgeSteps.ageStep(raw)
                        onPick((raw / step) * step)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

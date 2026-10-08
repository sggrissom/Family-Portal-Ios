import SwiftUI

/// **Everyone at {age}** — the family side by side at one age, from `GetSameAge`. A port of the web's `same-age.tsx`.
/// Two views: **Portraits** (faces, the default) and **Details** (measurements, milestones and photos). The first load asks the server which ages have anything, so Younger and Older skip the empty years for the view showing, the age list says how many people each has, and a direct visit starts at the richest comparison. Opened from a record or a link with a person and an age, it keeps that age even when nobody has anything there.
/// The server owns what counts as "at this age", the newborn window included; nothing here re-derives it.
struct SameAgeView: View {
    @State private var browser: SameAgeBrowser
    @State private var isPickingAge = false

    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    init(ageMonths: Int? = nil, fromRemoteId: Int = 0, view: SameAgeMode = .portraits) {
        _browser = State(initialValue: SameAgeBrowser(ageMonths: ageMonths, fromPersonId: fromRemoteId, mode: view))
    }

    private var isConnected: Bool { network?.isConnected ?? true }

    var body: some View {
        @Bindable var browser = browser
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker(Copy.sameAge.views, selection: $browser.mode) {
                    Text(Copy.sameAge.portraits).tag(SameAgeMode.portraits)
                    Text(Copy.sameAge.details).tag(SameAgeMode.details)
                }
                .pickerStyle(.segmented)

                if let response = browser.response {
                    controls(response)
                    status
                    if browser.failure == nil {
                        results(response)
                            .opacity(browser.isLoading ? 0.5 : 1)
                            .animation(.default, value: browser.isLoading)
                    }
                } else if let failure = browser.failure {
                    unavailable(failure)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle(browser.headingAge.map(AgeSteps.ageHeading) ?? Copy.sameAge.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard browser.response == nil, !browser.isLoading else { return }
            await browser.start(isConnected: isConnected)
        }
        .refreshable {
            await browser.refresh(isConnected: isConnected)
        }
        .sheet(isPresented: $isPickingAge) {
            if let selected = browser.selectedAge {
                if let options = browser.options {
                    AgeOptionsSheet(options: options, selected: selected, mode: browser.mode) { go(to: $0) }
                } else {
                    AgePickerSheet(initial: selected, maxMonths: browser.response?.maxAgeMonths ?? selected) { go(to: $0) }
                }
            }
        }
    }

    private func go(to age: Int) {
        Task { await browser.select(age, isConnected: isConnected) }
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(_ response: GetSameAgeResponseDTO) -> some View {
        let selected = browser.selectedAge ?? response.ageMonths

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AgeSteps.shortcuts, id: \.self) { age in
                    let isOn = selected == age
                    Button(AgeSteps.ageTitle(age)) { go(to: age) }
                        .buttonStyle(ShortcutButtonStyle(isOn: isOn))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.sameAge.shortcuts)

        HStack {
            Button {
                if let younger = browser.younger { go(to: younger) }
            } label: {
                Label(Copy.sameAge.younger, systemImage: "chevron.left")
            }
            .disabled(browser.younger == nil)

            Spacer()

            Button {
                isPickingAge = true
            } label: {
                HStack(spacing: 4) {
                    Text(AgeSteps.ageTitle(selected))
                        .font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
            }
            .accessibilityHint(Copy.sameAge.chooseAge)

            Spacer()

            Button {
                if let older = browser.older { go(to: older) }
            } label: {
                Label(Copy.sameAge.older, systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .disabled(browser.older == nil)
        }
        .buttonStyle(.bordered)

        if selected == 0 {
            Text(Copy.sameAge.newbornHelp)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// "Loading 3 years…", or what went wrong with **Try again** — in place, so the controls above never move.
    @ViewBuilder
    private var status: some View {
        if browser.isLoading, let selected = browser.selectedAge {
            HStack(spacing: 8) {
                ProgressView()
                Text(Copy.sameAge.loading(AgeSteps.ageTitle(selected)))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } else if let failure = browser.failure {
            HStack(alignment: .firstTextBaseline) {
                Text(failure == .offline ? Copy.sameAge.offline : Copy.sameAge.loadFailed)
                    .foregroundStyle(.secondary)
                Button(Copy.sameAge.retry) {
                    Task { await browser.retry(isConnected: isConnected) }
                }
            }
            .font(.subheadline)
        }
    }

    private func unavailable(_ failure: SameAgeBrowser.Failure) -> some View {
        ContentUnavailableView {
            Label(
                failure == .offline ? "You're offline" : "Couldn't load",
                systemImage: failure == .offline ? "wifi.slash" : "exclamationmark.triangle"
            )
        } description: {
            Text(failure == .offline ? "Same age needs a connection the first time it opens an age." : Copy.sameAge.loadFailed)
        } actions: {
            Button(Copy.sameAge.retry) {
                Task { await browser.retry(isConnected: isConnected) }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private func results(_ response: GetSameAgeResponseDTO) -> some View {
        // An older server sends no count; then an empty answer is the best evidence that nobody has a birthday.
        if (browser.peopleCount ?? response.rows.count) == 0 {
            Text(Copy.sameAge.empty)
                .foregroundStyle(.secondary)
        } else if browser.mode == .portraits {
            SameAgePortraits(rows: response.rows, ageMonths: response.ageMonths)
                .id(response.ageMonths)
        } else {
            SameAgeDetails(response: response, hasAnyRecords: browser.discovery.map { !$0.available.isEmpty } ?? true)
        }
    }
}

/// **Details** — the people with records at the age, how many that is, and how many have none, rather than a line apiece for them.
private struct SameAgeDetails: View {
    let response: GetSameAgeResponseDTO
    /// Whether the family has any record at any age, which decides what "nothing here" says.
    let hasAnyRecords: Bool

    var body: some View {
        let recorded = response.rows.filter { !$0.isEmpty }
        let missing = response.rows.count - recorded.count
        if recorded.isEmpty {
            Text(hasAnyRecords ? Copy.sameAge.nothingAtAge : Copy.sameAge.noSavedRecords)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(recorded.count == 1
                     ? "\(Copy.sameAge.peopleWithRecords(1)) · \(Copy.sameAge.onlyOne)"
                     : Copy.sameAge.peopleWithRecords(recorded.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SameAgeRows(rows: response.rows, ageMonths: response.ageMonths, hideEmpty: true)
                if missing > 0 {
                    Text(Copy.sameAge.missingRecords(missing))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ShortcutButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
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

/// The ages with something to see in the current view, each with how many people — and the age on screen even when it has nothing, so an explicitly chosen age is never missing from its own list.
private struct AgeOptionsSheet: View {
    let options: [SameAgeOptionDTO]
    let selected: Int
    let mode: SameAgeMode
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var rows: [SameAgeOptionDTO] {
        guard !options.contains(where: { $0.ageMonths == selected }) else { return options }
        return (options + [SameAgeOptionDTO(ageMonths: selected, peopleCount: 0)]).sorted { $0.ageMonths < $1.ageMonths }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(rows, id: \.ageMonths) { option in
                    Button {
                        onPick(option.ageMonths)
                        dismiss()
                    } label: {
                        HStack {
                            Text(AgeSteps.ageTitle(option.ageMonths))
                                .foregroundStyle(.primary)
                            if options.contains(option) {
                                Text("· \(mode == .portraits ? Copy.sameAge.pictured(option.peopleCount) : Copy.sameAge.withRecords(option.peopleCount))")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option.ageMonths == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityAddTraits(option.ageMonths == selected ? .isSelected : [])
                }
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
            }
            .navigationTitle(Copy.sameAge.chooseAge)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Years and months, snapped onto the age grid on the way out — for a server that sends no age list.
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
            .navigationTitle(Copy.sameAge.chooseAge)
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

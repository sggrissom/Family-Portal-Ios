import SwiftUI
import SwiftData
import OSLog

// MARK: - Shared form pieces

/// A date that may genuinely not be known. `OccurredAt` has no null on the wire, so the zero time is how "sometime that weekend" is stored.
struct ActivityDateField: Equatable {
    var isSet: Bool
    var day: Date

    init() {
        isSet = false
        day = .now
    }

    init(_ serverValue: Date) {
        if let known = serverValue.serverDate {
            isSet = true
            day = known.displayDay()
        } else {
            isSet = false
            day = .now
        }
    }

    /// What the write sends. `nil` clears the date, which is what the toggle being off means.
    var date: Date? { isSet ? day.localRecordDay() : nil }

    /// Both days known, and the end before the start.
    static func endsBeforeStart(_ start: ActivityDateField, _ end: ActivityDateField) -> Bool {
        guard let first = start.date, let last = end.date else { return false }
        return last < first
    }
}

struct AppearanceDateSection: View {
    @Binding var field: ActivityDateField
    let labels: ActivityLabels

    var body: some View {
        Section {
            Toggle("Know the day?", isOn: $field.isSet)
            if field.isSet {
                DatePicker("Day", selection: $field.day, displayedComponents: .date)
            }
        } footer: {
            if !field.isSet {
                Text("Left off, this \(labels.appearance.lowercased()) sorts by the \(labels.event.lowercased())'s own dates — which is usually what you want mid-weekend.")
            }
        }
    }
}

/// Round, opponent, outcome and an optional score, for a battle bracket or a tournament game. Open from the start for a sport or a matchup already recorded; otherwise behind a button, since most performances have no opponent. Two scores fill in the outcome they imply until one is picked by hand.
struct AppearanceMatchupSection: View {
    @Binding var draft: MatchupDraft
    let labels: ActivityLabels

    @State private var isOpen: Bool
    @State private var outcomeChosen: Bool

    init(draft: Binding<MatchupDraft>, labels: ActivityLabels) {
        _draft = draft
        self.labels = labels
        _isOpen = State(initialValue: labels == .sport || draft.wrappedValue.matchup.isRecorded)
        _outcomeChosen = State(initialValue: !draft.wrappedValue.outcome.isEmpty)
    }

    private var outcome: Binding<String> {
        Binding {
            draft.outcome
        } set: { value in
            draft.outcome = value
            outcomeChosen = !value.isEmpty
        }
    }

    var body: some View {
        if isOpen {
            Section {
                HStack {
                    TextField("Round", text: $draft.round)
                    Menu {
                        ForEach(Matchups.commonRounds, id: \.self) { round in
                            Button(round) { draft.round = round }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Common rounds")
                }
                TextField("Against", text: $draft.opponent)
                Picker("Outcome", selection: outcome) {
                    ForEach(MatchupOutcome.all, id: \.self) { option in
                        Text(MatchupOutcome.optionLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Score")
                    Spacer()
                    TextField("Us", text: $draft.scoreFor)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64)
                        .accessibilityLabel("Our score")
                    Text("–")
                    TextField("Them", text: $draft.scoreAgainst)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 64)
                        .accessibilityLabel("Their score")
                }
            } header: {
                Text("Head-to-head")
            } footer: {
                if let error = draft.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Leave the score empty when none was kept.")
                }
            }
            .onChange(of: draft.scoreFor) { fillOutcome() }
            .onChange(of: draft.scoreAgainst) { fillOutcome() }
        } else {
            Section {
                Button {
                    isOpen = true
                } label: {
                    Label("Head-to-head", systemImage: "plus")
                }
            } footer: {
                Text("For a bracket or a game: the round, who it was against, and whether the \(labels.entry.lowercased()) won.")
            }
        }
    }

    private func fillOutcome() {
        guard !outcomeChosen else { return }
        draft.outcome = draft.outcomeFromScore
    }
}

struct AppearanceNotesSection: View {
    @Binding var notes: String

    var body: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .onChange(of: notes) { _, new in
                    // The server truncates past this rather than refusing.
                    if new.count > ActivityFieldLimit.notes.characters {
                        notes = String(new.prefix(ActivityFieldLimit.notes.characters))
                    }
                }
        }
    }
}

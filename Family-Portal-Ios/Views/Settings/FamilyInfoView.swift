import SwiftUI

/// Surfaces `GetFamilyInfo` and `JoinFamily` (backend/users.go). Before this,
/// the `Family` model carried an `inviteCode` field that nothing outside
/// `PreviewData` ever read, so there was no way to invite anyone from the app.
struct FamilyInfoView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService: SyncService?

    @State private var info: FamilyInfoResponseDTO?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showJoinSheet = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let info, !info.families.isEmpty {
                ForEach(info.families, id: \.id) { family in
                    Section {
                        LabeledContent("Name", value: family.name)

                        if !family.inviteCode.isEmpty {
                            inviteCodeRow(family.inviteCode)
                        }
                    } header: {
                        HStack {
                            Text(family.name)
                            if family.isPrimary {
                                Text("Primary")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.tint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            } else if let loadError {
                Section {
                    ContentUnavailableView(
                        "Couldn't Load Family",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                }
            }

            Section {
                Button {
                    showJoinSheet = true
                } label: {
                    Label("Join a Family", systemImage: "person.badge.plus")
                }
            } footer: {
                Text("Enter an invite code someone shared with you.")
            }
        }
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showJoinSheet) {
            JoinFamilySheet {
                Task {
                    await load()
                    // A new membership changes what pullFamilyData returns.
                    await syncService?.performFullSync()
                }
            }
        }
    }

    @ViewBuilder
    private func inviteCodeRow(_ code: String) -> some View {
        HStack {
            Text("Invite Code")
            Spacer()
            Text(code)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ShareLink(item: code) {
                Image(systemName: "square.and.arrow.up")
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Share invite code")
        }
    }

    private func load() async {
        loadError = nil
        do {
            info = try await APIClient.shared.getFamilyInfo()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

/// Separate sheet so a failed join keeps its own error next to the field the
/// user typed into.
private struct JoinFamilySheet: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode = ""
    let onJoined: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $inviteCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } footer: {
                    Text("Ask a family member to share their invite code from Settings.")
                }

                if let error = authService.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Join a Family")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { authService.clearError() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task {
                            if await authService.joinFamily(inviteCode: inviteCode) {
                                onJoined()
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || authService.isLoading
                    )
                }
            }
        }
    }
}

import SwiftUI
import UIKit

/// The families the user belongs to, their invite codes, and the way into
/// another family. `GetFamilyInfo` and `JoinFamily` have always existed on the
/// backend and the `inviteCode` was unreachable from the app, so there was no
/// way to invite anyone or to accept an invitation on iOS.
struct FamilyInfoView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService: SyncService?

    @State private var inviteCode = ""
    @State private var loadError: String?
    @State private var joinError: String?
    @State private var isLoading = true
    @State private var isJoining = false

    private var trimmedInviteCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
            } else if authService.families.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Family",
                        systemImage: "person.2.slash",
                        description: Text(loadError ?? "You aren't part of a family yet. Enter an invite code below to join one.")
                    )
                }
            } else {
                ForEach(authService.families) { family in
                    familySection(family)
                }
            }

            joinSection
        }
        .navigationTitle("Families")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func familySection(_ family: FamilyInfoDTO) -> some View {
        Section {
            LabeledContent("Name", value: family.name)

            LabeledContent("Invite Code") {
                Text(family.inviteCode)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            Button {
                UIPasteboard.general.string = family.inviteCode
            } label: {
                Label("Copy Invite Code", systemImage: "doc.on.doc")
            }

            ShareLink(
                item: family.inviteCode,
                message: Text("Join our family on \(AppConstants.appName) with invite code \(family.inviteCode).")
            ) {
                Label("Share Invitation", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text(family.isPrimary ? "\(family.name) (Primary)" : family.name)
        } footer: {
            if family.isPrimary {
                Text("New people and photos you add go to your primary family.")
            }
        }
    }

    @ViewBuilder
    private var joinSection: some View {
        Section {
            TextField("Invite Code", text: $inviteCode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)

            Button {
                Task { await join() }
            } label: {
                HStack {
                    if isJoining {
                        ProgressView()
                    } else {
                        Text("Join Family")
                    }
                }
            }
            .disabled(trimmedInviteCode.isEmpty || isJoining)

            if let joinError {
                Text(joinError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        } header: {
            Text("Join a Family")
        } footer: {
            Text("Joining adds a family without leaving your own. Ask someone in that family for their invite code.")
        }
    }

    private func load() async {
        loadError = await authService.loadFamilyInfo()
        isLoading = false
    }

    private func join() async {
        joinError = nil
        isJoining = true
        defer { isJoining = false }

        if let failure = await authService.joinFamily(inviteCode: trimmedInviteCode) {
            joinError = failure
            return
        }

        inviteCode = ""
        // The new family's people only appear once the timeline is pulled again.
        await syncService?.pullFamilyData()
    }
}

#Preview {
    NavigationStack {
        FamilyInfoView()
            .environment(AuthService())
    }
}

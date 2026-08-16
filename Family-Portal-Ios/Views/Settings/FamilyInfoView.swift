import SwiftUI
import UIKit

/// The families the user belongs to, their invite codes, and the way into
/// another family. `GetFamilyInfo` and `JoinFamily` have always existed on the
/// backend and the `inviteCode` was unreachable from the app, so there was no
/// way to invite anyone or to accept an invitation on iOS.
///
/// The membership half lives one level down, in `FamilyMembershipView`; only
/// rotating the invite code is here, next to the code it replaces.
struct FamilyInfoView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService: SyncService?

    @State private var inviteCode = ""
    @State private var loadError: String?
    @State private var joinError: String?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var rotationTarget: FamilyInfoDTO?
    /// Keyed by family: with several families on screen, an unlabelled message
    /// would sit under whichever section the user happens to look at.
    @State private var rotationFailure: RotationFailure?
    @State private var isRotating = false

    private struct RotationFailure: Identifiable {
        /// The family the rotation was attempted on.
        let id: Int
        let message: String
    }

    private let membership = FamilyMembershipService()

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
        .confirmationDialog(
            "Generate New Code",
            isPresented: Binding(
                get: { rotationTarget != nil },
                set: { if !$0 { rotationTarget = nil } }
            ),
            presenting: rotationTarget
        ) { family in
            Button("Generate New Code", role: .destructive) {
                Task { await rotate(family) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { family in
            Text("Any code or link you have already shared for \(family.name) stops working, and anyone still waiting to join will need the new one.")
        }
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

            // An invite code is a bearer secret that gets pasted into messaging
            // apps. Being able to retire one without a support request is the
            // difference between a leak being a shrug and being a migration.
            Button {
                rotationTarget = family
            } label: {
                Label("Generate New Code", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isRotating)

            NavigationLink {
                FamilyMembershipView(family: family)
            } label: {
                Label("Members", systemImage: "person.2")
            }

            if let rotationFailure, rotationFailure.id == family.id {
                Text(rotationFailure.message)
                    .foregroundStyle(.red)
                    .font(.callout)
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

    private func rotate(_ family: FamilyInfoDTO) async {
        rotationFailure = nil
        isRotating = true
        defer { isRotating = false }

        do {
            let newCode = try await membership.rotateInviteCode(familyId: family.id)
            // The response is authoritative, so the section re-renders with the
            // new code without a second round trip to `GetFamilyInfo`.
            authService.applyRotatedInviteCode(newCode, forFamily: family.id)
        } catch {
            rotationFailure = RotationFailure(id: family.id, message: error.localizedDescription)
        }
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

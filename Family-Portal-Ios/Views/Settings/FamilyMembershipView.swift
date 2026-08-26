import SwiftUI

/// Who can sign in and see one family. Distinct from `FamilyMembersView` and `FamilyManagementView`, which list `Person` records — the family's people, not its accounts.
struct FamilyMembershipView: View {
    let family: FamilyInfoDTO

    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(\.dismiss) private var dismiss

    @State private var members: [FamilyMemberDTO] = []
    @State private var callerIsOwner = false
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var memberToRemove: FamilyMemberDTO?
    @State private var confirmingLeave = false

    private let membership = FamilyMembershipService()

    /// The caller's own membership row. Absent while loading, and for a family the account no longer belongs to.
    private var isMember: Bool {
        members.contains { $0.isSelf }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                membersSection
                leaveSection
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "Remove Member",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            ),
            presenting: memberToRemove
        ) { member in
            Button("Remove \(member.name)", role: .destructive) {
                Task { await remove(member) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.name) loses access to \(family.name) immediately. Anything they added — people, photos, measurements, milestones — stays with the family.")
        }
        .confirmationDialog("Leave Family", isPresented: $confirmingLeave) {
            Button("Leave \(family.name)", role: .destructive) {
                Task { await leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You lose access to \(family.name) immediately. Anything you added stays with the family, and you will need a new invite code to come back.")
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        Section {
            if members.isEmpty {
                Text("No members to show.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members) { member in
                    memberRow(member)
                }
            }
        } header: {
            Text(family.name)
        } footer: {
            Text(membersFooter)
        }
    }

    /// Only shown to somebody who has a member to remove: removing yourself is leaving.
    private var membersFooter: String {
        let shared = "Everyone here can see and edit this family's people, photos, measurements and milestones."

        guard callerIsOwner else {
            return "\(shared) Only \(ownerName) can remove members."
        }
        return members.contains { !$0.isSelf } ? "\(shared) Swipe a member to remove them." : shared
    }

    private var ownerName: String {
        members.first { $0.isOwner }?.name ?? "the family owner"
    }

    @ViewBuilder
    private func memberRow(_ member: FamilyMemberDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                Text(member.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if member.isOwner {
                badge("Owner")
            }
            if member.isSelf {
                badge("You")
            }
        }
        .swipeActions(edge: .trailing) {
            if callerIsOwner && !member.isSelf {
                Button("Remove", role: .destructive) {
                    memberToRemove = member
                }
                .disabled(isBusy)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var leaveSection: some View {
        if isMember {
            if members.count > 1 {
                Section {
                    Button("Leave \(family.name)", role: .destructive) {
                        confirmingLeave = true
                    }
                    .disabled(isBusy)
                } footer: {
                    Text("Leaving takes effect immediately and leaves everything you added with the family.")
                }
            } else {
                Section {
                    Text("You are the only member of this family. To remove it and everything in it, delete your account from Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() async {
        do {
            let response = try await membership.members(familyId: family.id)
            members = response.members
            callerIsOwner = response.callerIsOwner
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func remove(_ member: FamilyMemberDTO) async {
        isBusy = true
        defer { isBusy = false }

        do {
            members = try await membership.removeMember(familyId: family.id, userId: member.userId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leave() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let auth = try await membership.leaveFamily(familyId: family.id)
            await authService.applyLeftFamily(family.id, auth: auth)
            dismiss()

            // That family's people and photos stay on the device until a pull clears them.
            await syncService?.pullFamilyData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        FamilyMembershipView(
            family: FamilyInfoDTO(
                id: 1,
                name: "The Grissoms",
                inviteCode: "ABC123",
                role: 0,
                isPrimary: true
            )
        )
        .environment(AuthService())
    }
}

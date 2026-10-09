import Foundation

/// Membership self-service (backend/membership_procs.go). These are *accounts*, not the people a family keeps records about; removing a member leaves everything they entered.
/// Nothing here goes through `SyncQueue`: a membership change means nothing until the server agrees, so it is online only.
struct FamilyMembershipService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func members(familyId: Int) async throws -> ListFamilyMembersResponseDTO {
        try await apiClient.callRPC(
            .listFamilyMembers,
            payload: FamilyIdRequestDTO(familyId: familyId)
        )
    }

    func removeMember(familyId: Int, userId: Int) async throws -> [FamilyMemberDTO] {
        let response: RemoveFamilyMemberResponseDTO = try await apiClient.callRPC(
            .removeFamilyMember,
            payload: RemoveFamilyMemberRequestDTO(familyId: familyId, userId: userId)
        )
        return try response.accepted(or: "Could not remove that member.").members
    }

    func leaveFamily(familyId: Int) async throws -> AuthResponseDTO? {
        let response: FamilyChangeResponseDTO = try await apiClient.callRPC(
            .leaveFamily,
            payload: FamilyIdRequestDTO(familyId: familyId)
        )
        let auth = try response.accepted(or: "Could not leave this family.").auth

        // Go marshals a zero-valued struct rather than omitting it, so "no auth" arrives as a user with id 0.
        guard let auth, auth.id != 0 else { return nil }
        return auth
    }

    /// Replaces a family's invite code, retiring every code and link already
    /// shared. Returns the new one.
    func rotateInviteCode(familyId: Int) async throws -> String {
        let fallback = "Could not generate a new invite code."
        let response: RotateInviteCodeResponseDTO = try await apiClient.callRPC(
            .rotateInviteCode,
            payload: FamilyIdRequestDTO(familyId: familyId)
        )

        // An empty code with a success would leave the family showing its old, now-dead code.
        let code = try response.accepted(or: fallback).inviteCode
        guard !code.isEmpty else { throw ServerRefusal(message: fallback) }
        return code
    }
}

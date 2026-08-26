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

        guard response.success else {
            throw MembershipError.refused(response.error ?? "Could not remove that member.")
        }
        return response.members
    }

    func leaveFamily(familyId: Int) async throws -> AuthResponseDTO? {
        let response: LeaveFamilyResponseDTO = try await apiClient.callRPC(
            .leaveFamily,
            payload: FamilyIdRequestDTO(familyId: familyId)
        )

        guard response.success else {
            throw MembershipError.refused(response.error ?? "Could not leave this family.")
        }

        // Go marshals a zero-valued struct rather than omitting it, so "no auth" arrives as a user with id 0.
        guard let auth = response.auth, auth.id != 0 else { return nil }
        return auth
    }

    /// Replaces a family's invite code, retiring every code and link already
    /// shared. Returns the new one.
    func rotateInviteCode(familyId: Int) async throws -> String {
        let response: RotateInviteCodeResponseDTO = try await apiClient.callRPC(
            .rotateInviteCode,
            payload: FamilyIdRequestDTO(familyId: familyId)
        )

        // An empty code with a success would leave the family showing its old, now-dead code.
        guard response.success, !response.inviteCode.isEmpty else {
            throw MembershipError.refused(response.error ?? "Could not generate a new invite code.")
        }
        return response.inviteCode
    }
}

/// A refusal the backend carries in the response body rather than the status code: vbeam answers `{ success: false, error: … }` with HTTP 200.
enum MembershipError: LocalizedError {
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .refused(let message):
            return message
        }
    }
}

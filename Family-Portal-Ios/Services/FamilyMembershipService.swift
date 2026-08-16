import Foundation

/// Membership self-service (backend/membership_procs.go): who has access to a
/// family, and how somebody stops having it.
///
/// These are *accounts*, not the people a family keeps records about —
/// `FamilyManagementView` is the roster of `Person`s, and the two are unrelated:
/// removing a member takes away one login's access and leaves every person,
/// photo, measurement and milestone they entered with the family.
///
/// Nothing here goes through `SyncQueue`. A membership change is a permission
/// change: it means nothing until the server agrees, and a queued "leave family"
/// replayed hours later — against a family that already removed you, or after
/// you changed your mind — would report a success that never happened. Online
/// only, like `JoinFamily`.
struct FamilyMembershipService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// A zero `familyId` asks about the caller's primary family.
    func members(familyId: Int) async throws -> ListFamilyMembersResponseDTO {
        try await apiClient.callRPC(
            .listFamilyMembers,
            payload: FamilyIdRequestDTO(familyId: familyId)
        )
    }

    /// Drops somebody else's membership; only the family owner may. Returns the
    /// members that remain, which the response already carries.
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

    /// Gives up the caller's own membership. Returns their refreshed identity,
    /// since leaving can move which family is primary — nil when the server sent
    /// nothing usable, which is a value rather than a failure: the leave still
    /// happened.
    ///
    /// The backend refuses the last member of a family (the household's content
    /// would become unreachable), and that refusal arrives as `success: false`
    /// with a message meant for the user.
    func leaveFamily(familyId: Int) async throws -> AuthResponseDTO? {
        let response: LeaveFamilyResponseDTO = try await apiClient.callRPC(
            .leaveFamily,
            payload: FamilyIdRequestDTO(familyId: familyId)
        )

        guard response.success else {
            throw MembershipError.refused(response.error ?? "Could not leave this family.")
        }

        // Go marshals a zero-valued struct rather than omitting it, so "no auth"
        // arrives as a user with id 0 — adopting that would sign the app out of
        // an account that is still perfectly valid.
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

        // An empty code with a success would leave the family showing its old,
        // now-dead code as if nothing had happened.
        guard response.success, !response.inviteCode.isEmpty else {
            throw MembershipError.refused(response.error ?? "Could not generate a new invite code.")
        }
        return response.inviteCode
    }
}

/// A refusal the backend carries in the response body rather than the status
/// code: vbeam answers `{ success: false, error: … }` with HTTP 200, so the
/// message has to be lifted into an error to reach a `catch` alongside the
/// `APIError`s from the transport.
enum MembershipError: LocalizedError {
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .refused(let message):
            return message
        }
    }
}

import Foundation
import Testing
@testable import Family_Portal_Ios

/// `FamilyMembershipService` against a fake backend.
///
/// Membership refusals are the point of this suite. Every one of them arrives as
/// HTTP 200 with `{ success: false, error: … }` — the Go handlers put the message
/// in the body and return a nil error — so a service that only checked the status
/// code would report "you left the family" to somebody who is still very much in
/// it.
@MainActor
@Suite("Family membership")
struct FamilyMembershipTests {

    // MARK: - Fixtures
    //
    // Each returns `[String: Any]` explicitly: these bodies mix ints, bools and
    // nested arrays, and a bare literal in an `Any` position has no type to be
    // inferred from.

    private static func member(
        userId: Int,
        name: String,
        email: String? = nil,
        role: Int = 0,
        isOwner: Bool = false,
        isSelf: Bool = false
    ) -> [String: Any] {
        [
            "userId": userId,
            "name": name,
            "email": email ?? "\(name.lowercased())@example.com",
            "role": role,
            "joinedAt": "2026-01-05T12:00:00Z",
            "isOwner": isOwner,
            "isSelf": isSelf
        ]
    }

    private static func memberList(
        _ members: [[String: Any]],
        familyId: Int = 7,
        callerIsOwner: Bool = false
    ) -> [String: Any] {
        [
            "familyId": familyId,
            "members": members,
            "callerIsOwner": callerIsOwner
        ]
    }

    private static func removal(members: [[String: Any]]) -> [String: Any] {
        ["success": true, "members": members]
    }

    /// A refusal as the Go handlers write one: HTTP 200, `success: false`, and a
    /// message meant to be shown to the user.
    private static func refusal(_ message: String, members: Bool = false) -> [String: Any] {
        var body: [String: Any] = ["success": false, "error": message]
        if members {
            // A nil Go slice marshals as null, not as an absent key.
            body["members"] = NSNull()
        }
        return body
    }

    private static func auth(id: Int, name: String, familyId: Int?) -> [String: Any] {
        var auth: [String: Any] = [
            "id": id,
            "name": name,
            "email": "\(name.lowercased())@example.com",
            "isAdmin": false,
            "families": NSNull()
        ]
        if let familyId {
            auth["familyId"] = familyId
        }
        return auth
    }

    private static func service(_ server: FakeHTTPServer) -> FamilyMembershipService {
        FamilyMembershipService(apiClient: server.apiClient())
    }

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    // MARK: - Listing

    @Test("Listing keeps the server's order and its owner and self flags")
    func listMembers() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/ListFamilyMembers", respond: .json(Self.memberList([
            Self.member(userId: 1, name: "Ada", isOwner: true),
            Self.member(userId: 2, name: "Bea", isSelf: true)
        ])))

        let response = try await Self.service(server).members(familyId: 7)

        // Owner first, then join order: the backend sorts, and re-sorting here
        // would only be a second opinion that can disagree with it.
        #expect(response.members.map(\.userId) == [1, 2])
        #expect(response.members.first?.isOwner == true)
        #expect(response.members.last?.isSelf == true)
        #expect(response.members.last?.email == "bea@example.com")
        #expect(response.callerIsOwner == false)
    }

    @Test("A zero family id is sent as-is, since the server reads it as the primary family")
    func listSendsFamilyId() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/ListFamilyMembers", respond: .json(Self.memberList([], familyId: 3, callerIsOwner: true)))

        _ = try await Self.service(server).members(familyId: 0)

        let requests = server.requests(for: "rpc/ListFamilyMembers")
        #expect(requests.count == 1)
        #expect(try Self.body(of: requests[0])["familyId"] as? Int == 0)
    }

    /// `joinedAt` is the field this DTO deliberately ignores. It has to stay
    /// ignorable: decoding it would put a date parse between the user and the
    /// list, for a value nothing on screen shows.
    @Test("An unparseable joinedAt does not stop the list from decoding")
    func listIgnoresJoinedAt() async throws {
        let server = FakeHTTPServer()
        var member = Self.member(userId: 1, name: "Ada", isOwner: true)
        member["joinedAt"] = "not a date"
        server.route("rpc/ListFamilyMembers", respond: .json(Self.memberList([member], callerIsOwner: true)))

        let response = try await Self.service(server).members(familyId: 7)
        #expect(response.members.count == 1)
    }

    // MARK: - Removing

    @Test("A removal answers with the members that remain")
    func removeMember() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/RemoveFamilyMember", respond: .json(Self.removal(members: [
            Self.member(userId: 1, name: "Ada", isOwner: true, isSelf: true)
        ])))

        let remaining = try await Self.service(server).removeMember(familyId: 7, userId: 2)

        #expect(remaining.map(\.userId) == [1])

        let body = try Self.body(of: server.requests(for: "rpc/RemoveFamilyMember")[0])
        #expect(body["familyId"] as? Int == 7)
        #expect(body["userId"] as? Int == 2)
    }

    @Test("A refused removal throws the server's own message")
    func removeMemberRefused() async throws {
        let server = FakeHTTPServer()
        let message = "Only the family owner can remove members"
        server.route("rpc/RemoveFamilyMember", respond: .json(Self.refusal(message, members: true)))

        do {
            _ = try await Self.service(server).removeMember(familyId: 7, userId: 2)
            Issue.record("Expected the refusal to throw")
        } catch let error as MembershipError {
            #expect(error.localizedDescription == message)
        }
    }

    // MARK: - Leaving

    @Test("Leaving returns the refreshed identity, which may name a new primary family")
    func leaveFamily() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/LeaveFamily", respond: .json([
            "success": true,
            "auth": Self.auth(id: 4, name: "Bea", familyId: 9)
        ] as [String: Any]))

        let auth = try await Self.service(server).leaveFamily(familyId: 7)

        #expect(auth?.id == 4)
        #expect(auth?.familyId == 9)
    }

    /// `omitempty` does nothing for a Go struct field, so a response with nothing
    /// to say about the caller still carries a fully zero `AuthResponse`. Adopting
    /// that as the signed-in user would replace a valid session with user id 0.
    @Test("A zero-valued auth is reported as no auth rather than as user 0")
    func leaveIgnoresZeroAuth() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/LeaveFamily", respond: .json([
            "success": true,
            "auth": Self.auth(id: 0, name: "", familyId: nil)
        ] as [String: Any]))

        #expect(try await Self.service(server).leaveFamily(familyId: 7) == nil)
    }

    @Test("The last member of a family is refused, with the reason the server gave")
    func leaveRefusedForLastMember() async throws {
        let server = FakeHTTPServer()
        let message = "You are the only member of this family. Delete your account to remove it, or invite someone else first."
        server.route("rpc/LeaveFamily", respond: .json(Self.refusal(message)))

        do {
            _ = try await Self.service(server).leaveFamily(familyId: 7)
            Issue.record("Expected the refusal to throw")
        } catch let error as MembershipError {
            #expect(error.localizedDescription == message)
        }
    }

    // MARK: - Rotating the invite code

    @Test("Rotating answers with the code that replaces the old one")
    func rotateInviteCode() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/RotateInviteCode", respond: .json([
            "success": true,
            "familyId": 7,
            "inviteCode": "NEWCODE9"
        ] as [String: Any]))

        #expect(try await Self.service(server).rotateInviteCode(familyId: 7) == "NEWCODE9")
    }

    /// A success with no code would leave the family showing its old — now dead —
    /// code as though nothing had happened, which is worse than an error: the user
    /// would go on sharing a code that no longer works.
    @Test("A success carrying no code is treated as a failure")
    func rotateWithoutACodeFails() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/RotateInviteCode", respond: .json(["success": true]))

        await #expect(throws: MembershipError.self) {
            _ = try await Self.service(server).rotateInviteCode(familyId: 7)
        }
    }

    @Test("A transport failure surfaces as an APIError, not as a refusal")
    func rotateOffline() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/RotateInviteCode", respond: .offline())

        await #expect(throws: APIError.self) {
            _ = try await Self.service(server).rotateInviteCode(familyId: 7)
        }
    }

    // MARK: - The local family list

    /// Rotation updates the row in place rather than re-fetching, so the carried
    /// fields have to survive: a family that lost its name or its primary flag on
    /// the way through would look like a different family.
    @Test("A rotated code replaces only the code")
    func withInviteCodeKeepsEverythingElse() {
        let family = FamilyInfoDTO(
            id: 7,
            name: "The Grissoms",
            inviteCode: "OLDCODE1",
            role: 2,
            isPrimary: true
        )

        let rotated = family.withInviteCode("NEWCODE9")

        #expect(rotated.inviteCode == "NEWCODE9")
        #expect(rotated.id == 7)
        #expect(rotated.name == "The Grissoms")
        #expect(rotated.role == 2)
        #expect(rotated.isPrimary)
    }
}

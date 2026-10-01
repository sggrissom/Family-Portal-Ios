import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Tag management")
struct TagManagementTests {

    private static func service(_ server: FakeHTTPServer) -> TagService {
        TagService(apiClient: server.apiClient())
    }

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    @Test("A tag's auto-phrase decodes, and an absent one is empty")
    func decodesAutoPhrase() throws {
        var withPhrase = Fixture.tag(id: 3)
        withPhrase["autoPhrase"] = "kids at the lake cabin"
        let decoded = try APIClient.decode(TagDTO.self, from: JSONSerialization.data(withJSONObject: withPhrase))
        #expect(decoded.autoPhrase == "kids at the lake cabin")

        let without = try APIClient.decode(TagDTO.self, from: JSONSerialization.data(withJSONObject: Fixture.tag(id: 4)))
        #expect(without.autoPhrase == "")
    }

    @Test("Creating sends the name, colour and family, and returns the saved tag")
    func create() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateTag", respond: .json(["tag": Fixture.tag(id: 9, name: "Beach", color: "#ff8000")]))

        let tag = try await Self.service(server).create(name: "Beach", color: "#ff8000", familyId: 0)

        #expect(tag.id == 9)
        #expect(tag.name == "Beach")
        let body = try Self.body(of: try #require(server.requests(for: "rpc/CreateTag").first))
        #expect(body["name"] as? String == "Beach")
        #expect(body["color"] as? String == "#ff8000")
        #expect(body["familyId"] as? Int == 0)
    }

    @Test("Updating always sends the phrase, so clearing it reaches the server")
    func updateSendsEmptyPhrase() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/UpdateTag", respond: .json(["tag": Fixture.tag(id: 3, name: "Trips")]))

        let tag = try await Self.service(server).update(id: 3, name: "Trips", color: "#4A90D9", autoPhrase: "")

        #expect(tag.name == "Trips")
        let body = try Self.body(of: try #require(server.requests(for: "rpc/UpdateTag").first))
        #expect(body["id"] as? Int == 3)
        #expect(body["autoPhrase"] as? String == "")
    }

    @Test("Deleting accepts the server's empty response")
    func delete() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/DeleteTag", respond: .json([String: Any]()))

        try await Self.service(server).delete(id: 3)

        let body = try Self.body(of: try #require(server.requests(for: "rpc/DeleteTag").first))
        #expect(body["id"] as? Int == 3)
    }

    @Test("A refused duplicate surfaces as an error")
    func duplicateRefused() async {
        let server = FakeHTTPServer()
        server.route("rpc/CreateTag", respond: .status(400, message: "A tag with this name already exists"))

        await #expect(throws: (any Error).self) {
            _ = try await Self.service(server).create(name: "Beach", color: "#ff8000", familyId: 0)
        }
    }

    // MARK: - Colour back to hex

    @Test("Channels become lowercase #rrggbb")
    func hexFromChannels() {
        #expect(TagColor.hex(red: 1, green: 128.0 / 255, blue: 0) == "#ff8000")
        #expect(TagColor.hex(red: 74.0 / 255, green: 144.0 / 255, blue: 217.0 / 255) == "#4a90d9")
    }

    @Test("Out-of-range channels are clamped")
    func hexClamps() {
        #expect(TagColor.hex(red: 1.4, green: -0.2, blue: 0.5) == "#ff0080")
    }

    @Test("A parsed colour survives the trip back to hex")
    func hexRoundTrip() throws {
        let parsed = try #require(TagColor.components(forHex: "#6366F1"))
        #expect(TagColor.hex(red: parsed.red, green: parsed.green, blue: parsed.blue) == "#6366f1")
    }
}

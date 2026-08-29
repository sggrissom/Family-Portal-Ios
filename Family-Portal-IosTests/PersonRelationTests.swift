import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Person relationships")
struct PersonRelationTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private static func person(
        in harness: TestSync.Harness,
        name: String,
        remoteId: String?
    ) throws -> Person {
        let person = Person(name: name, gender: .other, birthday: Date())
        person.remoteId = remoteId
        harness.context.insert(person)
        try harness.context.save()
        return person
    }

    private static func routeAddPerson(_ harness: TestSync.Harness, relationship: String? = nil) {
        harness.server.route("rpc/AddPerson", respond: .json([
            "person": Fixture.person(id: 13, name: "Kate", relationship: relationship)
        ]))
    }

    // MARK: - Stating a relationship while adding

    @Test("A stated relationship travels with the person that states it")
    func addPersonSendsTheStatedEdge() async throws {
        let harness = try TestSync.harness(connected: false)
        let anchor = try Self.person(in: harness, name: "Ruth", remoteId: "12")
        let kate = try Self.person(in: harness, name: "Kate", remoteId: nil)
        Self.routeAddPerson(harness, relationship: "sister")

        try await harness.service.addPerson(kate, stated: .sibling, anchor: anchor)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddPerson").first))
        #expect(body["stated"] as? Int == StatedRelation.sibling.rawValue)
        #expect(body["anchorId"] as? Int == 12)
        #expect(kate.relationship == "sister")
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("Saying nothing sends nothing to relate to")
    func addPersonWithoutRelationSendsZeroes() async throws {
        let harness = try TestSync.harness(connected: false)
        let kate = try Self.person(in: harness, name: "Kate", remoteId: nil)
        Self.routeAddPerson(harness)

        try await harness.service.addPerson(kate)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddPerson").first))
        #expect(body["stated"] as? Int == 0)
        #expect(body["anchorId"] as? Int == 0)
        #expect(kate.relationship == nil)
    }

    @Test("A person related to someone still uploading waits rather than arriving unrelated")
    func unsyncedAnchorBlocksTheCreate() async throws {
        let harness = try TestSync.harness(connected: false)
        let anchor = try Self.person(in: harness, name: "Ruth", remoteId: nil)
        let kate = try Self.person(in: harness, name: "Kate", remoteId: nil)
        Self.routeAddPerson(harness, relationship: "sister")

        try await harness.service.addPerson(kate, stated: .sibling, anchor: anchor)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/AddPerson").isEmpty)
        #expect(await harness.service.syncQueue.count() == 1)

        // The anchor lands, and the create goes out with the relationship intact.
        anchor.remoteId = "12"
        try harness.context.save()
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddPerson").first))
        #expect(body["anchorId"] as? Int == 12)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    // MARK: - Editing a person

    @Test("An edit adopts the relationship the server words back")
    func updateAdoptsTheServersLabel() async throws {
        let harness = try TestSync.harness(connected: false)
        let kate = try Self.person(in: harness, name: "Kate", remoteId: "13")
        kate.relationship = "sister"
        try harness.context.save()

        // Every person-shaped response is labelled, so what comes back is authoritative — including a relationship that was removed on another device.
        harness.server.route("rpc/UpdatePerson", respond: .json([
            "person": Fixture.person(id: 13, name: "Kate Ann")
        ]))

        try await harness.service.updatePerson(kate)
        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(kate.name == "Kate Ann")
        #expect(kate.relationship == nil)
    }

    // MARK: - The relationship graph

    @Test("Relations come back with the server's own wording")
    func relationsAreReadFromTheServer() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetPersonRelations", respond: .json([
            "personId": 13,
            "relations": [
                ["id": 4, "personId": 12, "personName": "Ruth", "label": "mother"]
            ],
            "manageable": true
        ]))

        let relations = try await PersonRelationService(apiClient: server.apiClient())
            .relations(personId: 13)

        #expect(relations.personId == 13)
        #expect(relations.manageable)
        #expect(relations.relations.first?.label == "mother")
        #expect(relations.relations.first?.personName == "Ruth")
    }

    @Test("Adding an edge states direction and answers with the rebuilt list")
    func addRelationSendsDirection() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/AddRelation", respond: .json([
            "success": true,
            "relations": [
                "personId": 13,
                "relations": [
                    ["id": 4, "personId": 12, "personName": "Ruth", "label": "mother"]
                ],
                "manageable": true
            ]
        ]))

        let relations = try await PersonRelationService(apiClient: server.apiClient())
            .addRelation(personId: 13, anchorId: 12, stated: .child)

        let body = try Self.body(of: try #require(server.requests(for: "rpc/AddRelation").first))
        #expect(body["personId"] as? Int == 13)
        #expect(body["anchorId"] as? Int == 12)
        #expect(body["stated"] as? Int == StatedRelation.child.rawValue)
        #expect(relations.relations.count == 1)
    }

    @Test("A refusal in the body is an error, not an empty graph")
    func refusalIsNotAnEmptyGraph() async throws {
        // vbeam answers a refusal with HTTP 200, and `relations` is a struct, so it arrives zero-valued rather than absent.
        let server = FakeHTTPServer()
        server.route("rpc/AddRelation", respond: .json([
            "success": false,
            "error": "A person cannot be related to themselves",
            "relations": ["personId": 0, "relations": [], "manageable": false]
        ]))

        await #expect(throws: RelationError.self) {
            try await PersonRelationService(apiClient: server.apiClient())
                .addRelation(personId: 13, anchorId: 13, stated: .sibling)
        }
    }

    @Test("Removing an edge answers with what is left")
    func removeRelationReturnsTheRemainder() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/RemoveRelation", respond: .json([
            "success": true,
            "relations": ["personId": 13, "relations": [], "manageable": true]
        ]))

        let relations = try await PersonRelationService(apiClient: server.apiClient())
            .removeRelation(relationId: 4)

        let body = try Self.body(of: try #require(server.requests(for: "rpc/RemoveRelation").first))
        #expect(body["relationId"] as? Int == 4)
        #expect(relations.relations.isEmpty)
        #expect(relations.manageable)
    }
}

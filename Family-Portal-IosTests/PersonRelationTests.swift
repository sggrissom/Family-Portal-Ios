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

    @Test("Co-anchors travel with a new person, and are dropped if they cannot be named")
    func addPersonCarriesResolvableCoAnchors() async throws {
        let harness = try TestSync.harness(connected: false)
        let anchor = try Self.person(in: harness, name: "Steven", remoteId: "12")
        let coParent = try Self.person(in: harness, name: "Ruth", remoteId: "14")
        // Still uploading, so there is no id to send. The create must not be held back over a suggestion.
        let pending = try Self.person(in: harness, name: "Jo", remoteId: nil)
        let mia = try Self.person(in: harness, name: "Mia", remoteId: nil)
        Self.routeAddPerson(harness, relationship: "daughter")

        try await harness.service.addPerson(
            mia,
            stated: .child,
            anchor: anchor,
            additionalAnchors: [coParent, pending]
        )

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddPerson").first))
        #expect(body["anchorId"] as? Int == 12)
        #expect(body["additionalAnchorIds"] as? [Int] == [14])
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

    @Test("An edit sends the pregnancy flag it was opened with")
    func updateCarriesThePregnancyFlag() async throws {
        // `UpdatePerson` assigns this unconditionally: omitting it decodes as `false` on the Go side and quietly clears an unborn record.
        let harness = try TestSync.harness(connected: false)
        let bump = try Self.person(in: harness, name: "Baby", remoteId: "13")
        bump.isPregnancy = true
        try harness.context.save()

        harness.server.route("rpc/UpdatePerson", respond: .json([
            "person": Fixture.person(id: 13, name: "Baby", isPregnancy: true)
        ]))

        try await harness.service.updatePerson(bump)
        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdatePerson").first))
        #expect(body["isPregnancy"] as? Bool == true)
        #expect(bump.isPregnancy)
    }

    @Test("A new unborn record says so when it is created")
    func addPersonCarriesThePregnancyFlag() async throws {
        let harness = try TestSync.harness(connected: false)
        let bump = Person(name: "Baby", gender: .other, birthday: Date(), isPregnancy: true)
        harness.context.insert(bump)
        try harness.context.save()
        harness.server.route("rpc/AddPerson", respond: .json([
            "person": Fixture.person(id: 13, name: "Baby", isPregnancy: true)
        ]))

        try await harness.service.addPerson(bump)
        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddPerson").first))
        #expect(body["isPregnancy"] as? Bool == true)
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

    @Test("Implied rows are marked as such and never collide with each other")
    func impliedRowsAreDistinguished() async throws {
        // The server sends implied rows with id 0. Keyed on that they would collapse into one; keyed on the person they stay distinct.
        let server = FakeHTTPServer()
        server.route("rpc/GetPersonRelations", respond: .json([
            "personId": 13,
            "relations": [
                Fixture.relationView(id: 4, personId: 12, personName: "Ruth", label: "mother"),
                Fixture.relationView(id: 0, personId: 14, personName: "Ben", label: "brother", stored: false),
                Fixture.relationView(id: 0, personId: 15, personName: "Rose", label: "grandmother", stored: false),
            ],
            "manageable": true
        ]))

        let relations = try await PersonRelationService(apiClient: server.apiClient())
            .relations(personId: 13)

        let stored = relations.relations.filter(\.stored)
        let implied = relations.relations.filter { !$0.stored }
        #expect(stored.map(\.personName) == ["Ruth"])
        #expect(stored.first?.relationId == 4)
        #expect(implied.map(\.personName) == ["Ben", "Rose"])
        #expect(Set(relations.relations.map(\.id)).count == 3)
    }

    @Test("A server that predates the split sent only rows somebody typed")
    func rowsWithoutTheFlagAreStored() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetPersonRelations", respond: .json([
            "personId": 13,
            "relations": [["id": 4, "personId": 12, "personName": "Ruth", "label": "mother"]],
            "manageable": true
        ]))

        let relations = try await PersonRelationService(apiClient: server.apiClient())
            .relations(personId: 13)

        #expect(relations.relations.first?.stored == true)
    }

    @Test("One statement can be made against several people at once")
    func addRelationCarriesCoAnchors() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/AddRelation", respond: .json([
            "success": true,
            "relations": ["personId": 13, "relations": [], "manageable": true]
        ]))

        _ = try await PersonRelationService(apiClient: server.apiClient())
            .addRelation(personId: 13, anchorId: 12, stated: .child, additionalAnchorIds: [14, 15])

        let body = try Self.body(of: try #require(server.requests(for: "rpc/AddRelation").first))
        #expect(body["anchorId"] as? Int == 12)
        #expect(body["additionalAnchorIds"] as? [Int] == [14, 15])
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

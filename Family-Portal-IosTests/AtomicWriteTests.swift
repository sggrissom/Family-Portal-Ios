import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Atomic writes: checkups and milestone tags")
struct AtomicWriteTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private static func person(in harness: TestSync.Harness, remoteId: String? = "12") throws -> Person {
        let person = Person(name: "Rowan", gender: .other, birthday: Date())
        person.remoteId = remoteId
        harness.context.insert(person)
        try harness.context.save()
        return person
    }

    private static func checkup(in harness: TestSync.Harness, for person: Person) throws -> (height: GrowthData, weight: GrowthData) {
        let date = Date()
        let height = GrowthData(measurementType: .height, value: 34.5, unit: .inches, date: date)
        let weight = GrowthData(measurementType: .weight, value: 28.2, unit: .pounds, date: date)
        height.person = person
        weight.person = person
        harness.context.insert(height)
        harness.context.insert(weight)
        try harness.context.save()
        return (height, weight)
    }

    // MARK: - Checkups

    @Test("A checkup answer maps onto its records by type, not by position")
    func checkupResponseMapsByType() throws {
        let json: [String: Any] = ["growthData": [
            Fixture.growthData(id: 91, personId: 12, measurementType: 1, value: 28.2, unit: "lbs"),
            Fixture.growthData(id: 90, personId: 12, measurementType: 0, value: 34.5, unit: "in")
        ]]
        let response = try APIClient.decode(AddCheckupResponseDTO.self, from: JSONSerialization.data(withJSONObject: json))

        let height = GrowthData(measurementType: .height, value: 0, unit: .centimeters, date: Date())
        let weight = GrowthData(measurementType: .weight, value: 0, unit: .kilograms, date: Date())
        applyCheckupResponse(response, height: height, weight: weight)

        #expect(height.remoteId == "90")
        #expect(height.value == 34.5)
        #expect(weight.remoteId == "91")
        #expect(weight.value == 28.2)
    }

    @Test("A null growthData list decodes as empty")
    func checkupResponseToleratesNull() throws {
        let response = try APIClient.decode(AddCheckupResponseDTO.self, from: Data(#"{"growthData":null}"#.utf8))
        #expect(response.growthData.isEmpty)
    }

    @Test("Height and weight queue as one operation that waits on an unsynced person")
    func checkupQueuesOneOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.person(in: harness, remoteId: nil)
        let records = try Self.checkup(in: harness, for: person)

        try await harness.service.addCheckup([records.height, records.weight], for: person)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.type == .createCheckup)
        #expect(operation.localId == records.height.id.uuidString)
        #expect(operation.dependsOnLocalId == person.id.uuidString)

        let payload = try JSONDecoder().decode(CreateCheckupPayload.self, from: operation.payload)
        #expect(payload.weightLocalId == records.weight.id.uuidString)
        #expect(payload.heightUnit == "in")
        #expect(payload.weightUnit == "lbs")
    }

    @Test("A checkup with one value is an ordinary AddGrowthData")
    func singleValueCheckupUsesAddGrowthData() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.person(in: harness)
        let records = try Self.checkup(in: harness, for: person)

        try await harness.service.addCheckup([records.weight], for: person)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.map(\.type) == [.createGrowthData])
    }

    @Test("A queued checkup sends one AddCheckup and both records take the server's ids")
    func checkupExecutesAsOneCall() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.person(in: harness)
        let records = try Self.checkup(in: harness, for: person)
        harness.server.route("rpc/AddCheckup", respond: .json(["growthData": [
            Fixture.growthData(id: 90, personId: 12, measurementType: 0, value: 34.5, unit: "in"),
            Fixture.growthData(id: 91, personId: 12, measurementType: 1, value: 28.2, unit: "lbs")
        ]]))

        try await harness.service.addCheckup([records.height, records.weight], for: person)
        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let requests = harness.server.requests(for: "rpc/AddCheckup")
        #expect(requests.count == 1)
        #expect(harness.server.requests(for: "rpc/AddGrowthData").isEmpty)
        let body = try Self.body(of: try #require(requests.first))
        #expect(body["personId"] as? Int == 12)
        #expect(body["inputType"] as? String == "date")
        #expect((body["height"] as? [String: Any])?["unit"] as? String == "in")
        #expect((body["weight"] as? [String: Any])?["value"] as? Double == 28.2)

        #expect(records.height.remoteId == "90")
        #expect(records.weight.remoteId == "91")
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("A half deleted before the checkup runs is left out of it")
    func deletedHalfIsLeftOut() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.person(in: harness)
        let records = try Self.checkup(in: harness, for: person)
        harness.server.route("rpc/AddCheckup", respond: .json(["growthData": [
            Fixture.growthData(id: 91, personId: 12, measurementType: 1, value: 28.2, unit: "lbs")
        ]]))

        try await harness.service.addCheckup([records.height, records.weight], for: person)
        harness.context.delete(records.height)
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddCheckup").first))
        #expect(body["height"] == nil)
        #expect(body["weight"] != nil)
        #expect(records.weight.remoteId == "91")
    }

    // MARK: - Milestone tags

    @Test("A new milestone's tags travel in the AddMilestone call")
    func milestoneCreateCarriesTags() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.person(in: harness)
        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        harness.context.insert(milestone)
        try harness.context.save()
        harness.server.route("rpc/AddMilestone", respond: .json([
            "milestone": Fixture.milestone(id: 40, personId: 12, tagIds: [3, 5])
        ]))

        try await harness.service.addMilestone(milestone, for: person, tagRemoteIds: [3, 5])
        #expect(milestone.tagRemoteIds == [3, 5])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddMilestone").first))
        #expect(body["tagIds"] as? [Int] == [3, 5])
        #expect(harness.server.requests(for: "rpc/UpdateMilestoneTags").isEmpty)
    }

    @Test("An edit that did not show the tag picker leaves the tags alone")
    func milestoneUpdateOmitsTagsByDefault() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.person(in: harness)
        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        milestone.remoteId = "40"
        milestone.tagRemoteIds = [3]
        harness.context.insert(milestone)
        try harness.context.save()
        harness.server.route("rpc/UpdateMilestone", respond: .json([
            "milestone": Fixture.milestone(id: 40, personId: 12, tagIds: [3])
        ]))

        try await harness.service.updateMilestone(milestone)
        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdateMilestone").first))
        #expect(body["tagIds"] == nil)
        #expect(milestone.tagRemoteIds == [3])
    }

    @Test("A milestone payload queued by an older build decodes with no tags")
    func olderMilestonePayloadDecodes() throws {
        let json = #"{"personLocalId":"A","description":"x","category":"development","milestoneDate":"2026-01-05","photoLocalIds":null}"#
        let payload = try JSONDecoder().decode(CreateMilestonePayload.self, from: Data(json.utf8))
        #expect(payload.tagRemoteIds == nil)
    }
}

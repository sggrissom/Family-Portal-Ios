import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Quotes")
struct QuoteTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    @Test("A quote and its context come down from the server")
    func decodesQuote() throws {
        let json = try JSONSerialization.data(withJSONObject: Fixture.milestone(
            id: 40, personId: 12, description: "The moon is following our car!", category: "quote",
            context: "On the drive home"
        ))
        let dto = try APIClient.decode(MilestoneDTO.self, from: json)
        let milestone = milestoneFromDTO(dto)

        #expect(milestone.category == .quote)
        #expect(milestone.context == "On the drive home")
        #expect(milestone.displayText == "“The moon is following our car!”")
    }

    @Test("A milestone without context decodes as having none")
    func decodesMissingContext() throws {
        let json = try JSONSerialization.data(withJSONObject: Fixture.milestone(id: 40, personId: 12))
        let dto = try APIClient.decode(MilestoneDTO.self, from: json)
        #expect(dto.context == "")
        #expect(dto.displayText == "First steps")
    }

    @Test("Only quotation marks around the whole quote are dropped, as on the server")
    func unquote() {
        let cases: [(String, String)] = [
            (#""No, YOU'RE silly""#, "No, YOU'RE silly"),
            ("‘Why?’", "Why?"),
            (#"He said "no" twice"#, #"He said "no" twice"#),
            (#""Mine," then "yours""#, #""Mine," then "yours""#),
            ("'Twas the night before", "'Twas the night before"),
            (#""""#, #""""#),
            ("«Encore»", "Encore"),
        ]
        for (input, expected) in cases {
            #expect(Quotes.unquote(input) == expected)
        }
    }

    @Test("A new quote's context travels in the AddMilestone call")
    func createCarriesContext() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = Person(name: "Rowan", gender: .other, birthday: Date())
        person.remoteId = "12"
        harness.context.insert(person)
        let milestone = Milestone(descriptionText: "Can the dog come to school?", category: .quote, date: Date())
        milestone.context = "Watching the bus pull up"
        milestone.person = person
        harness.context.insert(milestone)
        try harness.context.save()
        harness.server.route("rpc/AddMilestone", respond: .json([
            "milestone": Fixture.milestone(id: 40, personId: 12, description: "Can the dog come to school?",
                                           category: "quote", context: "Watching the bus pull up")
        ]))

        try await harness.service.addMilestone(milestone, for: person)
        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddMilestone").first))
        #expect(body["category"] as? String == "quote")
        #expect(body["context"] as? String == "Watching the bus pull up")
    }

    @Test("A milestone payload queued by an older build decodes with no context")
    func olderPayloadDecodes() throws {
        let json = #"{"description":"x","category":"behavior","milestoneDate":"2026-01-05","photoLocalIds":null}"#
        let payload = try JSONDecoder().decode(UpdateMilestonePayload.self, from: Data(json.utf8))
        #expect(payload.context == nil)
    }
}

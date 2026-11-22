import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Recap link")
struct RecapLinkTests {

    private static func share(roster: String? = nil) -> CompetitionShare {
        CompetitionShare(
            eventName: "Nuvo Nashville",
            seasonName: "2025-26",
            dates: "Nov 8, 2025",
            place: "Nuvo · Nashville, TN",
            routines: [
                .init(
                    id: 1,
                    name: "Rise Up",
                    descriptors: "Group · Jazz",
                    roster: roster,
                    summary: nil,
                    performances: [
                        .init(id: 10, when: nil, matchup: nil, results: [
                            .init(kind: .placement, text: "1st of 14", detail: nil),
                            .init(kind: .award, text: "Judges' Choice", detail: "Technique · Individual"),
                        ]),
                    ]
                ),
            ],
            snapshotLabel: nil
        )
    }

    @Test("Sends what the preview holds, with the server's revision for each performance")
    func input() {
        let input = Self.share().recapInput(revisions: [10: 4])
        #expect(input == RecapInputDTO(
            eventName: "Nuvo Nashville",
            subtitle: "2025-26 · Nov 8, 2025",
            place: "Nuvo · Nashville, TN",
            snapshotLabel: "",
            routines: [
                RecapRoutineInputDTO(
                    entryId: 1,
                    name: "Rise Up",
                    descriptors: "Group · Jazz",
                    roster: "",
                    summary: "",
                    performances: [
                        RecapPerformanceInputDTO(
                            appearanceId: 10,
                            revision: 4,
                            when: "",
                            matchup: "",
                            results: [
                                RecapResultDTO(kind: "placement", text: "1st of 14", detail: ""),
                                RecapResultDTO(kind: "award", text: "Judges' Choice", detail: "Technique · Individual"),
                            ]
                        ),
                    ]
                ),
            ]
        ))
    }

    @Test("Names go only when the preview shows them")
    func names() throws {
        let hidden = try JSONEncoder().encode(Self.share().recapInput(revisions: [:]))
        #expect(!String(decoding: hidden, as: UTF8.self).contains("Clara"))

        let shown = Self.share(roster: "Clara, Ada").recapInput(revisions: [:])
        #expect(shown.routines.first?.roster == "Clara, Ada")
    }

    @Test("A link decodes with and without an expiry")
    func decodesLinks() throws {
        let json = """
        {"links":[
          {"id":2,"createdAt":"2026-11-21T20:17:10Z","expiresAt":"2026-12-21T20:17:10Z","expired":false,"createdByName":"Sam","canRevoke":true,"routineCount":3,"snapshotLabel":""},
          {"id":1,"createdAt":"2026-11-20T08:00:00Z","expired":true,"createdByName":"","canRevoke":false,"routineCount":1,"snapshotLabel":"Results so far, as of Nov 20, 2026"}
        ]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let links = try decoder.decode(ListRecapLinksResponseDTO.self, from: Data(json.utf8)).links
        #expect(links.map(\.id) == [2, 1])
        #expect(links[0].expiresAt != nil)
        #expect(links[1].expiresAt == nil)
        #expect(links[1].expired)
        #expect(links[1].snapshotLabel.hasPrefix("Results so far"))
    }
}

import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@Suite("Siri, Shortcuts and quick actions")
@MainActor
struct AppIntentsTests {

    /// An account that can add to family 9, decoded as the server sends it.
    private static func user(role: Int = FamilyAccess.contribute) throws -> AuthResponseDTO {
        let json = """
        {"id": 1, "name": "Sam", "email": "sam@example.com", "isAdmin": false, "familyId": 9,
         "families": [{"id": 9, "name": "Ours", "role": \(role), "isPrimary": true}]}
        """
        return try JSONDecoder().decode(AuthResponseDTO.self, from: Data(json.utf8))
    }

    private static func store() throws -> (ModelContext, Person) {
        let context = try TestStore.makeContext()
        let emma = Person(remoteId: "7", name: "Emma Rose", gender: .female)
        emma.familyRemoteId = 9
        context.insert(emma)
        try context.save()
        return (context, emma)
    }

    // MARK: - Add a quote

    @Test("A quote said to Siri is saved as today's quote by that person")
    func savesQuote() async throws {
        let (context, emma) = try Self.store()
        let today = try #require(DaySummaries.date(of: "2026-11-05"))

        let saved = try await QuickQuote.save("  “Bye bye moon”  ", personRemoteId: 7, context: context, syncService: nil, user: try Self.user(), today: today)

        #expect(saved.personName == "Emma")
        let milestones = try context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.count == 1)
        let quote = try #require(milestones.first)
        #expect(quote.category == .quote)
        #expect(quote.person?.id == emma.id)
        let recordTime = try #require(quote.recordTime)
        #expect(recordTime.from == WhenEntry.localDateString(today))
        #expect(recordTime.isExactDay)
        #expect(!quote.descriptionText.isEmpty)
    }

    @Test("Signed out, nothing is saved")
    func signedOutSavesNothing() async throws {
        let (context, _) = try Self.store()
        await #expect(throws: QuickQuote.Failure.signedOut) {
            _ = try await QuickQuote.save("Hi", personRemoteId: 7, context: context, syncService: nil, user: nil)
        }
        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

    @Test("A person this phone hasn't synced yet is refused")
    func unknownPerson() async throws {
        let (context, _) = try Self.store()
        await #expect(throws: QuickQuote.Failure.unknownPerson) {
            _ = try await QuickQuote.save("Hi", personRemoteId: 99, context: context, syncService: nil, user: try Self.user())
        }
    }

    @Test("A view-only member can't add a quote")
    func viewOnly() async throws {
        let (context, _) = try Self.store()
        await #expect(throws: QuickQuote.Failure.viewOnly) {
            _ = try await QuickQuote.save("Hi", personRemoteId: 7, context: context, syncService: nil, user: try Self.user(role: FamilyAccess.view))
        }
    }

    @Test("An empty quote is refused")
    func emptyQuote() async throws {
        let (context, _) = try Self.store()
        await #expect(throws: QuickQuote.Failure.empty) {
            _ = try await QuickQuote.save("   ", personRemoteId: 7, context: context, syncService: nil, user: try Self.user())
        }
    }

    // MARK: - Routing

    @Test("Quick actions name app-only destinations")
    func quickActionLinks() {
        #expect(QuickActions.link(for: "com.familyrecord.ios.add-photos") == .addPhotos)
        #expect(QuickActions.link(for: "com.familyrecord.ios.add-quote") == .addQuote(personRemoteId: nil))
        #expect(QuickActions.link(for: "com.familyrecord.ios.search") == .search(query: nil))
        #expect(QuickActions.link(for: "something-else") == nil)
    }

    /// The app-only destinations must never be reachable from a link, or a universal link could open the photo picker.
    @Test("No path parses to an app-only destination")
    func appOnlyLinksDontParse() {
        #expect(DeepLink.parse(path: "/search") == nil)
        #expect(DeepLink.parse(path: "/search?q=emma") == nil)
        #expect(DeepLink.parse(path: "/add-photos") == nil)
        #expect(DeepLink.parse(path: "/add-quote") == nil)
    }

    @Test("A quote form is its own add form")
    func quoteFormIdentity() {
        let id = UUID()
        #expect(AddForm.quote(personId: id).id != AddForm.milestone(personId: id).id)
    }
}

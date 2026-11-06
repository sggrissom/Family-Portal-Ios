import CoreSpotlight
import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@Suite("Spotlight indexing")
@MainActor
struct SpotlightIndexerTests {

    @Test("People and moments with a server id are indexed under their page's path")
    func entriesUseLinkPaths() throws {
        let context = try TestStore.makeContext()
        let emma = Person(remoteId: "7", name: "Emma Rose", gender: .female)
        let offline = Person(name: "Not Synced", gender: .male)
        context.insert(emma)
        context.insert(offline)
        let steps = Milestone(descriptionText: "First steps", category: .first, date: Date())
        steps.remoteId = "45"
        steps.person = emma
        context.insert(steps)
        try context.save()

        let entries = SpotlightIndexer.entries(in: context)

        #expect(Set(entries.map(\.id)) == ["/profile/7", "/milestone/45"])
        let milestone = try #require(entries.first { $0.id == "/milestone/45" })
        #expect(milestone.title == "First steps")
        #expect(milestone.text.contains("Emma"))
    }

    @Test("A quote is indexed in quotation marks")
    func quoteTitle() throws {
        let context = try TestStore.makeContext()
        let quote = Milestone(descriptionText: "Bye bye moon", category: .quote, date: Date())
        quote.remoteId = "3"
        context.insert(quote)
        try context.save()

        #expect(SpotlightIndexer.entries(in: context).first?.title == "“Bye bye moon”")
    }

    /// Interview answers stay out of system search, as they stay out of the widgets.
    @Test("Interview answers aren't indexed")
    func interviewAnswersStayOut() throws {
        let context = try TestStore.makeContext()
        let answer = Milestone(descriptionText: "Pizza", category: .interview, date: Date())
        answer.remoteId = "9"
        answer.interviewId = 2
        context.insert(answer)
        try context.save()

        #expect(SpotlightIndexer.entries(in: context).isEmpty)
    }

    @Test("Only what changed is sent, and what's gone is removed")
    func diffSendsChanges() {
        let same = SpotlightIndexer.Entry(id: "/profile/1", title: "Emma", text: "", date: nil, thumbnailRemoteId: nil)
        let edited = SpotlightIndexer.Entry(id: "/milestone/2", title: "First word", text: "", date: nil, thumbnailRemoteId: nil)
        let new = SpotlightIndexer.Entry(id: "/milestone/3", title: "First tooth", text: "", date: nil, thumbnailRemoteId: nil)
        let previous = [
            same.id: same.fingerprint,
            edited.id: "something else",
            "/milestone/4": "deleted since",
        ]

        let (changed, removed) = SpotlightIndexer.diff([same, edited, new], against: previous)

        #expect(changed.map(\.id) == ["/milestone/2", "/milestone/3"])
        #expect(removed == ["/milestone/4"])
    }

    @Test("A tapped result opens the record its identifier names")
    func resultOpensRecord() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "/milestone/45"]
        #expect(SpotlightIndexer.link(forActivity: activity) == .milestone(remoteId: 45))

        let person = NSUserActivity(activityType: CSSearchableItemActionType)
        person.userInfo = [CSSearchableItemActivityIdentifier: "/profile/7"]
        #expect(SpotlightIndexer.link(forActivity: person) == .person(remoteId: 7))
    }

    @Test("Indexing is on unless turned off")
    func enabledByDefault() throws {
        let name = "SpotlightIndexerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let indexer = SpotlightIndexer(defaults: defaults)

        #expect(indexer.isEnabled)
        defaults.set(false, forKey: SpotlightIndexer.enabledKey)
        #expect(!indexer.isEnabled)
    }
}

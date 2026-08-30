import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Relation graph")
struct RelationGraphTests {

    // Steven and Ruth are partners with two children, Mia and Ben. Kate is Ruth's sister.
    private enum Id {
        static let steven = 1
        static let ruth = 2
        static let mia = 3
        static let ben = 4
        static let kate = 5
    }

    private static let edges: [RelationEdge] = [
        RelationEdge(id: 1, fromId: Id.steven, toId: Id.mia, kind: .parent),
        RelationEdge(id: 2, fromId: Id.ruth, toId: Id.mia, kind: .parent),
        RelationEdge(id: 3, fromId: Id.steven, toId: Id.ben, kind: .parent),
        RelationEdge(id: 4, fromId: Id.steven, toId: Id.ruth, kind: .partner),
        RelationEdge(id: 5, fromId: Id.ruth, toId: Id.kate, kind: .sibling),
    ]

    // MARK: - Walking one step

    @Test("A parent edge points from the parent")
    func parentEdgesAreDirected() {
        #expect(Set(RelationGraph.parents(Self.edges, of: Id.mia)) == [Id.steven, Id.ruth])
        #expect(RelationGraph.parents(Self.edges, of: Id.steven).isEmpty)
        #expect(Set(RelationGraph.children(Self.edges, of: Id.steven)) == [Id.mia, Id.ben])
    }

    @Test("Partner and sibling edges read the same from either end")
    func symmetricEdgesReadBothWays() {
        #expect(RelationGraph.partners(Self.edges, of: Id.steven) == [Id.ruth])
        #expect(RelationGraph.partners(Self.edges, of: Id.ruth) == [Id.steven])
        #expect(RelationGraph.siblings(Self.edges, of: Id.kate) == [Id.ruth])
    }

    @Test("Siblings include the ones a shared parent implies")
    func sharedParentMakesSiblings() {
        // Nobody stated that Mia and Ben are siblings; they share Steven.
        #expect(RelationGraph.siblings(Self.edges, of: Id.mia) == [Id.ben])
        #expect(RelationGraph.siblings(Self.edges, of: Id.ben) == [Id.mia])
    }

    @Test("A stated sibling edge does not carry on to the next person")
    func siblingEdgesAreNotTransitive() {
        // Ruth–Kate and Kate–Jo does not make Ruth–Jo: half-siblings break that, which is why the co-anchor list exists.
        let jo = 6
        let edges = Self.edges + [RelationEdge(id: 6, fromId: Id.kate, toId: jo, kind: .sibling)]

        #expect(!RelationGraph.siblings(edges, of: Id.ruth).contains(jo))
        #expect(Set(RelationGraph.siblings(edges, of: Id.kate)) == [Id.ruth, jo])
    }

    @Test("A person is never their own sibling")
    func nobodyIsTheirOwnSibling() {
        #expect(!RelationGraph.siblings(Self.edges, of: Id.mia).contains(Id.mia))
    }

    // MARK: - Co-anchor suggestions

    @Test("A lone partner is offered as the other parent, already ticked")
    func singlePartnerIsPreselected() {
        // A new child of Steven's is almost always Ruth's too.
        let suggestions = RelationGraph.coAnchorSuggestions(
            Self.edges, stated: .child, personId: 0, anchorId: Id.steven
        )

        #expect(suggestions.map(\.anchorId) == [Id.ruth])
        #expect(suggestions.allSatisfy { $0.defaultChecked })
    }

    @Test("More than one partner is ambiguous, so nothing is ticked for the user")
    func severalPartnersAreNotPreselected() {
        let second = 7
        let edges = Self.edges + [RelationEdge(id: 7, fromId: Id.steven, toId: second, kind: .partner)]

        let suggestions = RelationGraph.coAnchorSuggestions(
            edges, stated: .child, personId: 0, anchorId: Id.steven
        )

        #expect(Set(suggestions.map(\.anchorId)) == [Id.ruth, second])
        #expect(suggestions.allSatisfy { !$0.defaultChecked })
    }

    @Test("Stating a parent or a sibling offers the anchor's siblings, unticked")
    func parentAndSiblingOfferSiblings() {
        for stated in [StatedRelation.parent, .sibling] {
            let suggestions = RelationGraph.coAnchorSuggestions(
                Self.edges, stated: stated, personId: 0, anchorId: Id.ruth
            )
            #expect(suggestions.map(\.anchorId) == [Id.kate])
            #expect(suggestions.allSatisfy { !$0.defaultChecked })
        }
    }

    @Test("A partner is nobody else's partner, so there is nothing to offer")
    func partnerOffersNothing() {
        #expect(RelationGraph.coAnchorSuggestions(
            Self.edges, stated: .partner, personId: 0, anchorId: Id.steven
        ).isEmpty)
        #expect(RelationGraph.coAnchorSuggestions(
            Self.edges, stated: .none, personId: 0, anchorId: Id.steven
        ).isEmpty)
    }

    @Test("Somebody the relation already holds against is not offered again")
    func alreadyStatedIsNotOffered() {
        // Mia is already Ruth's child, so adding Steven as a parent must not offer Ruth a second time.
        #expect(RelationGraph.coAnchorSuggestions(
            Self.edges, stated: .child, personId: Id.mia, anchorId: Id.steven
        ).isEmpty)
    }

    @Test("Neither the subject nor the anchor is offered as a co-anchor")
    func subjectAndAnchorAreExcluded() {
        // Ruth has two sisters. Stating that Kate is Ruth's sister may offer the other one, but never Kate herself and never Ruth.
        let jo = 8
        let edges = Self.edges + [RelationEdge(id: 8, fromId: Id.ruth, toId: jo, kind: .sibling)]

        let suggestions = RelationGraph.coAnchorSuggestions(
            edges, stated: .sibling, personId: Id.kate, anchorId: Id.ruth
        )

        #expect(suggestions.map(\.anchorId) == [jo])
    }

    @Test("Nothing is offered against nobody")
    func noAnchorOffersNothing() {
        #expect(RelationGraph.coAnchorSuggestions(
            Self.edges, stated: .child, personId: 0, anchorId: 0
        ).isEmpty)
    }
}

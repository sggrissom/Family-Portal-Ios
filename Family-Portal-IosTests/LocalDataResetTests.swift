import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// SwiftData survives a sign-out, so the records of whoever used the device last
/// are still there when the next account signs in. The pull heals the timeline —
/// `removeOrphans` drops what the server no longer lists — but chat is merged,
/// never reconciled, so the previous account's conversation stays on screen
/// until it is erased outright.
@MainActor
@Suite("Local data reset")
struct LocalDataResetTests {

    private static func scratchDefaults() -> UserDefaults {
        let name = "LocalDataResetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Ownership

    @Test("A store with no recorded owner is neither owned nor a mismatch")
    func unrecordedOwnerIsNotAMismatch() {
        let owner = LocalAccountOwner(defaults: Self.scratchDefaults())

        #expect(owner.hasRecordedOwner == false)
        #expect(owner.holdsDataForAnotherAccount(than: 7) == false)
    }

    @Test("The same account signing back in keeps its data")
    func sameAccountKeepsData() {
        let owner = LocalAccountOwner(defaults: Self.scratchDefaults())
        owner.record(userId: 7)

        #expect(owner.hasRecordedOwner)
        #expect(owner.holdsDataForAnotherAccount(than: 7) == false)
    }

    @Test("A different account signing in on the same device is a mismatch")
    func differentAccountIsAMismatch() {
        let owner = LocalAccountOwner(defaults: Self.scratchDefaults())
        owner.record(userId: 7)

        #expect(owner.holdsDataForAnotherAccount(than: 8))
    }

    /// Id 0 is what `integer(forKey:)` reads a missing key as, so an account
    /// that really is user 0 must not read as "no owner recorded".
    @Test("A recorded owner of zero is still a recorded owner")
    func zeroIsARecordedOwner() {
        let owner = LocalAccountOwner(defaults: Self.scratchDefaults())
        owner.record(userId: 0)

        #expect(owner.holdsDataForAnotherAccount(than: 8))
        #expect(owner.holdsDataForAnotherAccount(than: 0) == false)
    }

    @Test("Recording the new owner ends the mismatch")
    func recordingAdoptsTheStore() {
        let owner = LocalAccountOwner(defaults: Self.scratchDefaults())
        owner.record(userId: 7)
        owner.record(userId: 8)

        #expect(owner.holdsDataForAnotherAccount(than: 8) == false)
        #expect(owner.holdsDataForAnotherAccount(than: 7))
    }

    // MARK: - Erasing

    @Test("Every kind of local record is erased")
    func erasesTheWholeStore() async throws {
        let context = try TestStore.makeContext()

        let family = Family(name: "Grissom", inviteCode: "ABC123")
        context.insert(family)
        let person = Person(name: "Ada", type: .child, gender: .female, birthday: Date())
        person.family = family
        context.insert(person)
        let growth = GrowthData(measurementType: .height, value: 100, unit: .centimeters, date: Date())
        growth.person = person
        context.insert(growth)
        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        context.insert(milestone)
        context.insert(Photo(title: "Beach", descriptionText: "", photoDate: Date()))
        context.insert(FamilyTag(name: "Holiday", colorHex: "#4A90D9", familyId: 1))
        context.insert(ChatMessage(
            clientMessageId: UUID().uuidString,
            userId: 1,
            userName: "Ada",
            content: "private"
        ))
        context.insert(User(name: "Ada", email: "ada@example.com"))
        try context.save()

        await LocalDataReset.erase(.everything, context: context, syncQueue: TestStore.makeQueue())

        let families = try context.fetchCount(FetchDescriptor<Family>())
        let people = try context.fetchCount(FetchDescriptor<Person>())
        let growthData = try context.fetchCount(FetchDescriptor<GrowthData>())
        let milestones = try context.fetchCount(FetchDescriptor<Milestone>())
        let photos = try context.fetchCount(FetchDescriptor<Photo>())
        let tags = try context.fetchCount(FetchDescriptor<FamilyTag>())
        let messages = try context.fetchCount(FetchDescriptor<ChatMessage>())
        let users = try context.fetchCount(FetchDescriptor<User>())

        #expect(families == 0)
        #expect(people == 0)
        #expect(growthData == 0)
        #expect(milestones == 0)
        #expect(photos == 0)
        #expect(tags == 0)
        #expect(messages == 0)
        #expect(users == 0)
    }

    /// A queued operation carries no identity of its own, so anything the last
    /// account left unsent would be pushed under the new account's session, into
    /// the new account's family.
    @Test("Work the previous account left queued is dropped")
    func erasesThePendingQueue() async throws {
        let context = try TestStore.makeContext()
        let queue = TestStore.makeQueue()
        let operation = try SyncQueueTests.operation(
            .createPerson,
            localId: UUID().uuidString,
            payload: ["name": "Ada"]
        )
        await queue.enqueue(operation)
        let queuedBefore = await queue.count()
        #expect(queuedBefore == 1)

        await LocalDataReset.erase(.everything, context: context, syncQueue: queue)

        let queuedAfter = await queue.count()
        #expect(queuedAfter == 0)
    }

    /// The migration case: a store that predates any record of who owns it. Only
    /// chat is dropped, because it is the only thing the next pull cannot
    /// reconcile — and a queue built before this bookkeeping still belongs to
    /// the user who is signing in.
    @Test("A chat-only erase leaves the timeline and the queue alone")
    func chatOnlyErasePreservesEverythingElse() async throws {
        let context = try TestStore.makeContext()
        let queue = TestStore.makeQueue()
        let operation = try SyncQueueTests.operation(
            .createPerson,
            localId: UUID().uuidString,
            payload: ["name": "Ada"]
        )
        await queue.enqueue(operation)

        context.insert(Person(name: "Ada", type: .child, gender: .female, birthday: Date()))
        context.insert(Photo(title: "Beach", descriptionText: "", photoDate: Date()))
        context.insert(ChatMessage(
            clientMessageId: UUID().uuidString,
            userId: 1,
            userName: "Ada",
            content: "private"
        ))
        try context.save()

        await LocalDataReset.erase(.chatOnly, context: context, syncQueue: queue)

        let messages = try context.fetchCount(FetchDescriptor<ChatMessage>())
        let people = try context.fetchCount(FetchDescriptor<Person>())
        let photos = try context.fetchCount(FetchDescriptor<Photo>())
        let queued = await queue.count()

        #expect(messages == 0)
        #expect(people == 1)
        #expect(photos == 1)
        #expect(queued == 1)
    }
}

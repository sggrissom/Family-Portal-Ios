import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// The gallery's filter. Worth testing in its own right because a filter that is
/// wrong shows nothing wrong: a photo it excludes by mistake simply isn't there,
/// and the user reads that as the photo never having synced.
///
/// The rules mirror `frontend/hooks/usePhotoFilter.ts` — OR within a category, AND
/// across them — plus the search field, which the web has no equivalent for.
@MainActor
@Suite("Photo filter")
struct PhotoFilterTests {

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func makePhoto(
        in context: ModelContext,
        title: String = "Beach",
        description: String = "",
        date: Date = PhotoFilterTests.makeDate(2026, 1, 5),
        people: [Person] = [],
        tagIds: [Int] = []
    ) throws -> Photo {
        let photo = Photo(title: title, descriptionText: description, photoDate: date)
        photo.tagRemoteIds = tagIds
        context.insert(photo)
        photo.taggedPeople = people
        try context.save()
        return photo
    }

    private static func makePerson(in context: ModelContext, name: String) throws -> Person {
        let person = Person(name: name, type: .child, gender: .other, birthday: makeDate(2019, 8, 4))
        context.insert(person)
        try context.save()
        return person
    }

    // MARK: - Nothing selected

    @Test("An empty filter is not a filter")
    func emptyFilterKeepsEverything() throws {
        let context = try TestStore.makeContext()
        let photos = [
            try Self.makePhoto(in: context, title: "One"),
            try Self.makePhoto(in: context, title: "Two")
        ]

        let filter = PhotoFilter()
        #expect(!filter.isActive)
        #expect(!filter.hasPanelFilters)
        #expect(filter.apply(to: photos).count == 2)
    }

    /// Whitespace is not a search. The search bar reports "no results" for
    /// anything it cannot match, and a stray space would empty the whole grid.
    @Test("Whitespace-only search is not a filter")
    func whitespaceSearchKeepsEverything() throws {
        let context = try TestStore.makeContext()
        let photos = [try Self.makePhoto(in: context, title: "One")]

        var filter = PhotoFilter()
        filter.searchText = "   "

        #expect(!filter.isActive)
        #expect(filter.apply(to: photos).count == 1)
    }

    // MARK: - People and tags

    @Test("Selected people are OR-ed, and an untagged photo is not a match")
    func peopleAreOred() throws {
        let context = try TestStore.makeContext()
        let rowan = try Self.makePerson(in: context, name: "Rowan")
        let sam = try Self.makePerson(in: context, name: "Sam")
        let kit = try Self.makePerson(in: context, name: "Kit")

        let withRowan = try Self.makePhoto(in: context, title: "Rowan", people: [rowan])
        let withSam = try Self.makePhoto(in: context, title: "Sam", people: [sam])
        let withKit = try Self.makePhoto(in: context, title: "Kit", people: [kit])
        let familyPhoto = try Self.makePhoto(in: context, title: "Nobody")

        var filter = PhotoFilter()
        filter.personLocalIds = [rowan.id, sam.id]

        let visible = filter.apply(to: [withRowan, withSam, withKit, familyPhoto])
        #expect(visible.map(\.title) == ["Rowan", "Sam"])
    }

    @Test("Selected tags are OR-ed")
    func tagsAreOred() throws {
        let context = try TestStore.makeContext()
        let holiday = try Self.makePhoto(in: context, title: "Holiday", tagIds: [1])
        let birthday = try Self.makePhoto(in: context, title: "Birthday", tagIds: [2, 3])
        let untagged = try Self.makePhoto(in: context, title: "Untagged")

        var filter = PhotoFilter()
        filter.tagRemoteIds = [1, 3]

        #expect(filter.apply(to: [holiday, birthday, untagged]).map(\.title) == ["Holiday", "Birthday"])
    }

    /// Within a category the choices widen the result; across categories they
    /// narrow it. Getting this backwards is the difference between "Rowan's
    /// holiday photos" and "everything of Rowan's plus every holiday photo".
    @Test("Categories narrow each other")
    func categoriesAreAnded() throws {
        let context = try TestStore.makeContext()
        let rowan = try Self.makePerson(in: context, name: "Rowan")

        let both = try Self.makePhoto(in: context, title: "Both", people: [rowan], tagIds: [1])
        let personOnly = try Self.makePhoto(in: context, title: "Person only", people: [rowan])
        let tagOnly = try Self.makePhoto(in: context, title: "Tag only", tagIds: [1])

        var filter = PhotoFilter()
        filter.personLocalIds = [rowan.id]
        filter.tagRemoteIds = [1]

        #expect(filter.apply(to: [both, personOnly, tagOnly]).map(\.title) == ["Both"])
    }

    // MARK: - Dates

    /// The load-bearing half of the date window: a photo carries a time of day,
    /// so a `to` of the 5th taken literally excludes everything shot on the 5th
    /// after midnight — which is all of it.
    @Test("The end of the window includes the whole of its last day")
    func toDateIncludesTheWholeDay() throws {
        let context = try TestStore.makeContext()
        let morning = try Self.makePhoto(in: context, title: "Morning", date: Self.makeDate(2026, 1, 5, hour: 8))
        let evening = try Self.makePhoto(in: context, title: "Evening", date: Self.makeDate(2026, 1, 5, hour: 23))
        let nextDay = try Self.makePhoto(in: context, title: "Next day", date: Self.makeDate(2026, 1, 6, hour: 1))

        var filter = PhotoFilter()
        filter.dateTo = Self.makeDate(2026, 1, 5, hour: 9)

        #expect(filter.apply(to: [morning, evening, nextDay]).map(\.title) == ["Morning", "Evening"])
    }

    @Test("The start of the window includes the whole of its first day")
    func fromDateIncludesTheWholeDay() throws {
        let context = try TestStore.makeContext()
        let dayBefore = try Self.makePhoto(in: context, title: "Day before", date: Self.makeDate(2026, 1, 4, hour: 23))
        let morning = try Self.makePhoto(in: context, title: "Morning", date: Self.makeDate(2026, 1, 5, hour: 1))

        var filter = PhotoFilter()
        filter.dateFrom = Self.makeDate(2026, 1, 5, hour: 18)

        #expect(filter.apply(to: [dayBefore, morning]).map(\.title) == ["Morning"])
    }

    /// The web swaps a backwards range rather than matching nothing, and a date
    /// picker makes it easy to enter one; an empty grid would read as a bug.
    @Test("A range entered backwards is swapped, not treated as empty")
    func reversedRangeIsSwapped() throws {
        let context = try TestStore.makeContext()
        let inside = try Self.makePhoto(in: context, title: "Inside", date: Self.makeDate(2026, 1, 5))
        let outside = try Self.makePhoto(in: context, title: "Outside", date: Self.makeDate(2026, 2, 20))

        var filter = PhotoFilter()
        filter.dateFrom = Self.makeDate(2026, 1, 31)
        filter.dateTo = Self.makeDate(2026, 1, 1)

        #expect(filter.apply(to: [inside, outside]).map(\.title) == ["Inside"])
    }

    @Test("One end of the window is enough")
    func openEndedRangeWorks() throws {
        let context = try TestStore.makeContext()
        let old = try Self.makePhoto(in: context, title: "Old", date: Self.makeDate(2025, 6, 1))
        let recent = try Self.makePhoto(in: context, title: "Recent", date: Self.makeDate(2026, 6, 1))

        var filter = PhotoFilter()
        filter.dateFrom = Self.makeDate(2026, 1, 1)

        #expect(filter.apply(to: [old, recent]).map(\.title) == ["Recent"])
        #expect(filter.hasPanelFilters)
    }

    // MARK: - Search

    @Test("Search matches title and description, ignoring case and accents")
    func searchMatchesTitleAndDescription() throws {
        let context = try TestStore.makeContext()
        let byTitle = try Self.makePhoto(in: context, title: "Beach Day")
        let byDescription = try Self.makePhoto(in: context, title: "Untitled", description: "A day at the BEACH")
        let accented = try Self.makePhoto(in: context, title: "José's birthday")
        let other = try Self.makePhoto(in: context, title: "Snow")

        var filter = PhotoFilter()
        filter.searchText = "beach"
        #expect(filter.apply(to: [byTitle, byDescription, accented, other]).map(\.title) == ["Beach Day", "Untitled"])

        filter.searchText = "jose"
        #expect(filter.apply(to: [byTitle, byDescription, accented, other]).map(\.title) == ["José's birthday"])
    }

    /// Search is typed into the navigation bar, where it is already visible.
    /// Filling in the toolbar's filter glyph for it would report a panel state
    /// the panel does not have.
    @Test("Search counts as active but not as a panel filter")
    func searchIsNotAPanelFilter() {
        var filter = PhotoFilter()
        filter.searchText = "beach"

        #expect(filter.isActive)
        #expect(!filter.hasPanelFilters)
    }

    @Test("Clearing the panel leaves the search term alone")
    func clearingPanelKeepsSearch() {
        var filter = PhotoFilter()
        filter.personLocalIds = [UUID()]
        filter.tagRemoteIds = [1]
        filter.dateFrom = Self.makeDate(2026, 1, 1)
        filter.dateTo = Self.makeDate(2026, 2, 1)
        filter.searchText = "beach"

        filter.clearPanelFilters()

        #expect(!filter.hasPanelFilters)
        #expect(filter.isActive)
        #expect(filter.searchText == "beach")
    }

    // MARK: - Summary

    @Test("A single person is named; several are counted")
    func summaryNamesOnePerson() {
        let rowan = UUID()
        let sam = UUID()
        let names = [rowan: "Rowan", sam: "Sam"]

        var filter = PhotoFilter()
        filter.personLocalIds = [rowan]
        #expect(filter.summary(peopleNames: { names[$0] }) == "Rowan")

        filter.personLocalIds = [rowan, sam]
        #expect(filter.summary(peopleNames: { names[$0] }) == "2 people")
    }

    @Test("The summary names every active category")
    func summaryCoversEveryCategory() {
        var filter = PhotoFilter()
        filter.tagRemoteIds = [1, 2]
        filter.dateFrom = Self.makeDate(2026, 1, 1)

        let summary = filter.summary(peopleNames: { _ in nil })
        #expect(summary.contains("2 tags"))
        #expect(summary.contains("from"))

        // Search is deliberately absent: the search bar is showing it.
        filter.searchText = "beach"
        #expect(!filter.summary(peopleNames: { _ in nil }).contains("beach"))
    }

    @Test("An unnamed person still counts")
    func summaryHandlesAnUnknownPerson() {
        var filter = PhotoFilter()
        filter.personLocalIds = [UUID()]

        // A person deleted between opening the panel and reading the summary: the
        // filter still excludes photos, so the summary must still say something.
        #expect(filter.summary(peopleNames: { _ in nil }) == "1 person")
    }
}

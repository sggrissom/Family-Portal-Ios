import Foundation
import Testing
@testable import Family_Portal_Ios

/// The reading cases from frontend/lib/book.test.ts, over small hand-built books rather than the web's generated samples.
@MainActor
@Suite("Books")
struct BookTests {

    private static let birthday = "2024-03-14T00:00:00Z"

    private static func day(_ offset: Int) -> String {
        BookDay.addDays("2024-03-14", offset) + "T00:00:00Z"
    }

    // MARK: - A first year

    private static let juniper = BookPersonDTO(id: 1, name: "Juniper", birthday: birthday)

    private static func firstYearSources() -> BookSourcesDTO {
        BookSourcesDTO(
            people: [juniper],
            milestones: [
                BookMilestoneDTO(id: 1, personId: 1, description: "Smiled at me", category: "first", milestoneDate: day(20)),
                BookMilestoneDTO(id: 2, personId: 1, description: "Rolled over", milestoneDate: day(100)),
                BookMilestoneDTO(id: 3, personId: 1, description: "Blew out a candle", milestoneDate: day(365)),
            ],
            photos: [
                BookImageDTO(id: 10, description: "Hospital", photoDate: day(5)),
                BookImageDTO(id: 11, title: "IMG_1234", photoDate: day(6)),
                BookImageDTO(id: 12, title: "Home", photoDate: day(7)),
                BookImageDTO(id: 13, photoDate: day(365)),
                BookImageDTO(id: 14, photoDate: day(40), status: 1),
            ],
            growthData: [
                BookGrowthDTO(id: 1, personId: 1, measurementType: 1, value: 7.25, unit: "lbs", measurementDate: day(0)),
                BookGrowthDTO(id: 2, personId: 1, measurementType: 1, value: 11.5, unit: "lbs", measurementDate: day(60)),
            ],
            photoPeople: [10: [1], 11: [1], 12: [1], 13: [1]]
        )
    }

    private static func firstYearBook(items: [BookItemDTO]? = nil, showGrowth: Bool = true) -> BookDTO {
        BookDTO(
            personIds: [1],
            preset: BookPreset.firstYear,
            title: "Juniper's first year",
            startDate: "2024-03-14T00:00:00Z",
            endDate: "2025-03-14T00:00:00Z",
            coverPhotoId: 12,
            showGrowth: showGrowth,
            items: items ?? [
                BookItemDTO(kind: .photo, sourceId: 10),
                BookItemDTO(kind: .photo, sourceId: 11),
                BookItemDTO(kind: .photo, sourceId: 12),
                BookItemDTO(kind: .milestone, sourceId: 1),
                BookItemDTO(kind: .milestone, sourceId: 2),
                BookItemDTO(kind: .milestone, sourceId: 3),
                BookItemDTO(kind: .photo, sourceId: 13),
            ]
        )
    }

    private static func assemble(_ book: BookDTO, _ sources: BookSourcesDTO) -> AssembledBook {
        BookAssembler(book: book, sources: sources).assemble()
    }

    @Test("The first year ends the day before the first birthday, and a leap-day birthday rolls to March 1")
    func firstYearRange() {
        #expect(BookDay.addYears("2024-02-29", 1) == "2025-03-01")
        #expect(BookDay.addYears("2024-03-14", 1) == "2025-03-14")
        let book = Self.assemble(Self.firstYearBook(), Self.firstYearSources())
        #expect(book.dates == "March 14, 2024 – March 13, 2025")
        #expect(book.ending == "Juniper, one year old")
    }

    @Test("Chapters run welcome, months of age, growth, then the first birthday")
    func firstYearChapters() {
        let book = Self.assemble(Self.firstYearBook(), Self.firstYearSources())
        #expect(book.chapters.map(\.id) == ["welcome", "months-3", "growth", "birthday"])
        #expect(book.chapters.map(\.title) == ["Welcome to the world", "Three months", "How you grew", "Turning one"])
        #expect(book.chapters[0].dates == "March – April 2024")
        #expect(book.chapters[1].dates == "June – July 2024")
        #expect(book.chapters[3].dates == "March 14, 2025")
    }

    @Test("The welcome chapter opens on the birth facts, then a hero photo, the rest, and a first")
    func welcomeBlocks() {
        let book = Self.assemble(Self.firstYearBook(), Self.firstYearSources())
        let blocks = book.chapters[0].blocks
        #expect(blocks.count == 4)
        guard blocks.count == 4 else { return }
        #expect(blocks[0] == .facts(["Born March 14, 2024", "Weighed 7 lb 4 oz at birth"]))
        if case .hero(let photo) = blocks[1] {
            #expect(photo.id == 10)
            #expect(photo.caption == "Hospital")
            #expect(photo.detail == "5 days")
        } else {
            Issue.record("Expected a hero, got \(blocks[1])")
        }
        if case .photos(let photos) = blocks[2] {
            #expect(photos.map(\.id) == [11, 12])
            #expect(photos.map(\.caption) == ["", "Home"])
        } else {
            Issue.record("Expected photos, got \(blocks[2])")
        }
        if case .moment(let moment, let photo) = blocks[3] {
            #expect(moment.first)
            #expect(moment.text == "Smiled at me")
            #expect(photo == nil)
        } else {
            Issue.record("Expected a moment, got \(blocks[3])")
        }
    }

    @Test("A measurement taken days after the birth says so rather than claiming it was at birth")
    func birthFactsAreHonest() {
        let sources = Self.firstYearSources()
        let later = BookSourcesDTO(
            people: sources.people,
            milestones: sources.milestones,
            photos: sources.photos,
            growthData: [BookGrowthDTO(id: 1, personId: 1, measurementType: 1, value: 6.8, unit: "lbs", measurementDate: Self.day(3))],
            photoPeople: sources.photoPeople
        )
        let book = Self.assemble(Self.firstYearBook(), later)
        #expect(book.chapters[0].blocks.first == .facts(["Born March 14, 2024", "Weighed 6 lb 12.8 oz at 3 days old"]))
        #expect(!book.chapters.map(\.id).contains("growth"))
    }

    @Test("The closing chapter keeps first-birthday records, and the letter goes last")
    func closingChapter() {
        let base = Self.firstYearBook()
        let book = BookDTO(
            personIds: base.personIds, preset: base.preset, title: base.title, startDate: base.startDate, endDate: base.endDate,
            letter: "We love you.", signature: "Mom and Dad", items: base.items
        )
        let closing = Self.assemble(book, Self.firstYearSources()).chapters.last
        #expect(closing?.title == "Turning one")
        #expect(closing?.blocks.last == .letter(text: "We love you.", signature: "Mom and Dad"))
        if case .notes(let moments)? = closing?.blocks.first {
            #expect(moments.map(\.text) == ["Blew out a candle"])
            #expect(moments.first?.detail == "1 year")
        } else {
            Issue.record("Expected notes to open the closing chapter")
        }
    }

    @Test("A book-only caption replaces the photo's own")
    func bookCaption() {
        var items = Self.firstYearBook().items
        items[0] = BookItemDTO(kind: .photo, sourceId: 10, caption: "Only in the book")
        let book = Self.assemble(Self.firstYearBook(items: items), Self.firstYearSources())
        if case .hero(let photo) = book.chapters[0].blocks[1] {
            #expect(photo.caption == "Only in the book")
        } else {
            Issue.record("Expected a hero")
        }
    }

    @Test("Deleted, unready and unknown items are skipped and counted")
    func missingItems() {
        let items = Self.firstYearBook().items + [
            BookItemDTO(kind: .milestone, sourceId: 999),
            BookItemDTO(kind: .photo, sourceId: 14),
        ]
        let book = Self.assemble(Self.firstYearBook(items: items), Self.firstYearSources())
        #expect(book.missing == 2)
        let ids = book.chapters.flatMap(\.items)
        #expect(!ids.contains(7) && !ids.contains(8))
    }

    @Test("The growth chapter is left out when it is switched off")
    func growthSwitchedOff() {
        let book = Self.assemble(Self.firstYearBook(showGrowth: false), Self.firstYearSources())
        #expect(!book.chapters.map(\.id).contains("growth"))
    }

    @Test("The cover is the saved cover photo")
    func cover() {
        let book = Self.assemble(Self.firstYearBook(), Self.firstYearSources())
        #expect(book.cover?.id == 12)
    }

    // MARK: - Grouping

    @Test("Quiet months fold into a neighbour, and a chapter spans at most three")
    func groupsMonths() {
        #expect(BookAssembler.groupMonths([9, 0, 0, 1, 8, 0, 0, 0, 0, 0, 9]) == [[0], [3, 4], [10]])
        #expect(BookAssembler.groupMonths([1, 1, 1, 1, 1, 1]) == [[0, 1, 2], [3, 4, 5]])
    }

    @Test("Chapters are named by age")
    func chapterTitles() {
        #expect(BookAssembler.chapterTitle(from: 1, to: 1) == "One month")
        #expect(BookAssembler.chapterTitle(from: 4, to: 6) == "Four to six months")
    }

    @Test("Names join with commas and a final and")
    func joinsNames() {
        #expect(BookAssembler.joinNames(["Ava"]) == "Ava")
        #expect(BookAssembler.joinNames(["Ava", "Ben"]) == "Ava and Ben")
        #expect(BookAssembler.joinNames(["Ava", "Ben", "Cy"]) == "Ava, Ben and Cy")
    }

    @Test("Month spans name the year once when they share it")
    func monthSpans() {
        #expect(BookDay.monthSpan("2025-02-01", "2025-02-20") == "February 2025")
        #expect(BookDay.monthSpan("2025-02-01", "2025-04-01") == "February – April 2025")
        #expect(BookDay.monthSpan("2024-11-01", "2025-01-01") == "November 2024 – January 2025")
    }

    // MARK: - A family year

    private static func familyBook() -> (BookDTO, BookSourcesDTO) {
        let theo = BookPersonDTO(id: 2, name: "Theo", birthday: "2021-06-01T00:00:00Z")
        let sources = BookSourcesDTO(
            people: [juniper, theo],
            milestones: [
                BookMilestoneDTO(id: 30, personId: 2, description: "I'm a big boy now", category: "quote", milestoneDate: "2025-07-04T00:00:00Z"),
            ],
            photos: [
                BookImageDTO(id: 20, photoDate: "2025-02-10T00:00:00Z"),
                BookImageDTO(id: 21, photoDate: "2025-05-05T00:00:00Z"),
                BookImageDTO(id: 22, photoDate: "2025-08-08T00:00:00Z"),
            ],
            photoPeople: [20: [1, 2], 21: [2], 22: [1]]
        )
        let book = BookDTO(
            personIds: [1, 2],
            preset: BookPreset.familyYear,
            title: "Our 2025",
            startDate: "2025-01-01T00:00:00Z",
            endDate: "2026-01-01T00:00:00Z",
            showGrowth: false,
            items: [
                BookItemDTO(kind: .photo, sourceId: 20),
                BookItemDTO(kind: .photo, sourceId: 21),
                BookItemDTO(kind: .photo, sourceId: 22),
                BookItemDTO(kind: .milestone, sourceId: 30),
            ]
        )
        return (book, sources)
    }

    @Test("A photo of both children is shared once; each child gets their own section")
    func familySections() {
        let (book, sources) = Self.familyBook()
        let assembled = Self.assemble(book, sources)
        #expect(assembled.dates == "January 1, 2025 – December 31, 2025")
        #expect(assembled.chapters.map(\.id) == ["together-1", "person-1", "person-2"])
        #expect(assembled.chapters.map(\.title) == ["February 2025", "Juniper", "Theo"])
        #expect(assembled.chapters[0].items == [0])
        #expect(assembled.chapters[1].items == [2])
        #expect(assembled.chapters[2].items == [1, 3])
        #expect(assembled.chapters[1].dates == "Age 0 to 1")
        #expect(assembled.chapters[2].dates == "Age 3 to 4")
        #expect(assembled.ending == "Our 2025")
    }

    @Test("A shared photo says who is in it; a quote gets its own block")
    func familyDetails() {
        let (book, sources) = Self.familyBook()
        let assembled = Self.assemble(book, sources)
        if case .hero(let photo) = assembled.chapters[0].blocks.first {
            #expect(photo.detail == "Juniper and Theo")
        } else {
            Issue.record("Expected a hero in the shared chapter")
        }
        #expect(assembled.chapters[2].blocks.contains {
            if case .quote(let moment) = $0 { return moment.text == "I'm a big boy now" }
            return false
        })
    }

    // MARK: - Decoding

    @Test("GetBook decodes with Go's nulls and photoPeople's string keys")
    func decodesGetBook() throws {
        let payload: [String: Any] = [
            "book": [
                "id": 5, "familyId": 7, "personId": 1, "personIds": [1], "preset": "first-year",
                "title": "Juniper's first year", "startDate": "2024-03-14T00:00:00Z", "endDate": "2025-03-14T00:00:00Z",
                "coverPhotoId": 12, "density": "balanced", "categories": NSNull(), "match": "any",
                "introduction": "", "letter": "", "signature": "", "showGrowth": true,
                "items": [["kind": 1, "sourceId": 12, "photoId": 0, "caption": "", "pinned": true]],
                "excluded": NSNull(), "revision": 3,
            ],
            "sources": [
                "people": [Fixture.person(id: 1, name: "Juniper", birthday: Self.birthday)],
                "milestones": [Fixture.milestone(id: 1, personId: 1, milestoneDate: Self.day(20))],
                "photos": [Fixture.image(id: 12, photoDate: Self.day(7))],
                "growthData": NSNull(),
                "photoPeople": ["12": [1], "13": NSNull()],
                "untagged": NSNull(),
            ],
            "canEdit": true,
            "now": "2026-10-01T12:00:00Z",
        ]
        let response = try APIClient.decode(GetBookResponseDTO.self, from: Fixture.data(payload))
        #expect(response.book.id == 5)
        #expect(response.book.categories.isEmpty)
        #expect(response.book.items.first?.itemKind == .photo)
        #expect(response.book.items.first?.pinned == true)
        #expect(response.sources.photoPeople[12] == [1])
        #expect(response.sources.photoPeople[13] == [])
        #expect(response.sources.growthData.isEmpty)
        #expect(response.sources.people.first?.birthday == Self.birthday)
        #expect(response.canEdit)
    }

    @Test("ListBooks decodes a shelf")
    func decodesShelf() throws {
        let payload: [String: Any] = [
            "books": [[
                "id": 5, "personIds": [1, 2], "personNames": ["Juniper", "Theo"], "preset": "family-year",
                "title": "Our 2025", "startDate": "2025-01-01T00:00:00Z", "endDate": "2026-01-01T00:00:00Z",
                "coverPhotoId": 0, "updatedAt": "2026-09-30T10:00:00Z",
            ]],
            "canEdit": false,
        ]
        let response = try APIClient.decode(ListBooksResponseDTO.self, from: Fixture.data(payload))
        #expect(response.books.map(\.title) == ["Our 2025"])
        #expect(response.books.first?.personNames == ["Juniper", "Theo"])
        #expect(BookDay.bookDates(start: response.books[0].startDate, end: response.books[0].endDate) == "January 1, 2025 – December 31, 2025")
    }

    @Test("Book proc names match the backend")
    func procNames() {
        #expect(RPCMethod.listBooks.rawValue == "ListBooks")
        #expect(RPCMethod.getBook.rawValue == "GetBook")
    }
}

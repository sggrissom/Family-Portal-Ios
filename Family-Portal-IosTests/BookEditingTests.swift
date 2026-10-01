import Foundation
import Testing
@testable import Family_Portal_Ios

/// The suggesting cases from frontend/lib/book.test.ts and bookPlans.test.ts.
@MainActor
@Suite("Book editing")
struct BookEditingTests {

    private static func day(_ offset: Int) -> String {
        BookDay.addDays("2024-03-14", offset) + "T00:00:00Z"
    }

    /// A year with a photo every three days, a few milestones (two with photos attached) and a quote.
    private static func sources() -> BookSourcesDTO {
        var photos: [BookImageDTO] = []
        var photoPeople: [Int: [Int]] = [:]
        for (n, offset) in stride(from: 3, through: 330, by: 3).enumerated() {
            let id = 100 + n
            photos.append(BookImageDTO(id: id, width: n.isMultiple(of: 3) ? 600 : 800, height: 700, photoDate: day(offset)))
            photoPeople[id] = [1]
        }
        photos.append(BookImageDTO(id: 900, photoDate: day(45)))
        photos.append(BookImageDTO(id: 901, photoDate: day(200)))
        photoPeople[900] = [1]
        photoPeople[901] = [1]
        return BookSourcesDTO(
            people: [BookPersonDTO(id: 1, name: "Juniper", birthday: "2024-03-14T00:00:00Z")],
            milestones: [
                BookMilestoneDTO(id: 1, personId: 1, description: "First smile", category: "first", milestoneDate: day(45), photoIds: [900]),
                BookMilestoneDTO(id: 2, personId: 1, description: "Sat up", milestoneDate: day(160)),
                BookMilestoneDTO(id: 3, personId: 1, description: "Ba!", category: "quote", milestoneDate: day(250)),
                BookMilestoneDTO(id: 4, personId: 1, description: "Finger painting", category: "artwork", milestoneDate: day(200), photoIds: [901]),
            ],
            photos: photos,
            photoPeople: photoPeople
        )
    }

    private static func plan(categories: [String] = []) -> BookDTO {
        BookDTO(
            personIds: [1],
            preset: BookPreset.firstYear,
            title: "Juniper's first year",
            startDate: "2024-03-14T00:00:00Z",
            endDate: "2025-03-14T00:00:00Z",
            categories: categories,
            items: []
        )
    }

    private static func draft(_ density: BookDensity, categories: [String] = []) -> BookDTO {
        BookAssembler.draft(plan(categories: categories), sources: sources(), density: density)
    }

    private static func photoIds(_ book: BookDTO) -> [Int] {
        book.items.compactMap { item in
            switch item.itemKind {
            case .photo: return item.sourceId
            case .milestone: return item.photoId == 0 ? nil : item.photoId
            case nil: return nil
            }
        }
    }

    @Test("Picks spread across days instead of one busy day")
    func spreadsPicks() {
        let days = Array(repeating: "2024-05-01", count: 10) + ["2024-05-10", "2024-05-20"]
        #expect(BookAssembler.spreadPick(days, day: { $0 }, budget: 3) == ["2024-05-01", "2024-05-10", "2024-05-20"])
    }

    @Test("A draft is deterministic and uses each photo once, never the cover again")
    func draftsDeterministically() {
        let a = Self.draft(.balanced)
        let b = Self.draft(.balanced)
        #expect(a.items == b.items)
        #expect(a.coverPhotoId == b.coverPhotoId)
        let ids = Self.photoIds(a)
        #expect(Set(ids).count == ids.count)
        #expect(a.coverPhotoId != 0)
        #expect(!ids.contains(a.coverPhotoId))
    }

    @Test("A longer book uses more photos, and every milestone is kept")
    func densityAndMilestones() {
        let brief = Self.draft(.brief)
        let detailed = Self.draft(.detailed)
        #expect(Self.photoIds(detailed).count > Self.photoIds(brief).count)
        #expect(brief.items.filter { $0.itemKind == .milestone }.count == 4)
        #expect(brief.items.contains(.milestone(1, photoId: 900)))
    }

    @Test("A first year's cover is past the first two months")
    func coverIsSettled() {
        let book = Self.draft(.balanced)
        let cover = Self.sources().photos.first { $0.id == book.coverPhotoId }
        #expect(cover.map { BookDay.monthsOld("2024-03-14", BookDay.dayOf($0.photoDate)) >= 2 } == true)
        #expect(cover.map { $0.width >= $0.height } == true)
    }

    @Test("Picking again keeps kept photos and the order, and leaves removed ones out")
    func repicks() {
        let book = Self.draft(.detailed)
        let photos = book.items.filter { $0.itemKind == .photo }
        var pinned = photos[5]
        pinned.pinned = true
        let removed = photos[6]
        let reordered = [pinned] + book.items.filter { $0.key != pinned.key }

        let next = BookAssembler(book: book, sources: Self.sources()).suggest(
            density: .brief,
            current: reordered,
            excluded: [removed],
            coverPhotoId: book.coverPhotoId
        )
        #expect(next.items.first == pinned)
        #expect(!next.items.map(\.key).contains(removed.key))
        #expect(next.items.filter { $0.itemKind == .photo }.count < photos.count)
        #expect(next.coverPhotoId == book.coverPhotoId)
    }

    @Test("Only the chosen kinds of content are suggested")
    func followsCategories() {
        let book = Self.draft(.balanced, categories: ["quotes"])
        #expect(book.items == [.milestone(3)])
    }

    @Test("Records created after the last review are offered, and only until they are placed")
    func offersAdditions() {
        let base = Self.sources()
        var book = Self.draft(.balanced)
        book.reviewedAt = "2026-06-01T00:00:00-05:00"
        #expect(BookAssembler(book: book, sources: base).additions(since: book.reviewedAt, items: book.items, excluded: []).isEmpty)

        let late = BookMilestoneDTO(id: 99, personId: 1, description: "Waved", milestoneDate: Self.day(100), createdAt: "2026-06-02T00:00:00.123456789Z")
        let withLate = BookSourcesDTO(people: base.people, milestones: base.milestones + [late], photos: base.photos, photoPeople: base.photoPeople)
        let assembler = BookAssembler(book: book, sources: withLate)
        let fresh = assembler.additions(since: book.reviewedAt, items: book.items, excluded: [])
        #expect(fresh == [.milestone(99)])
        #expect(assembler.additions(since: book.reviewedAt, items: book.items, excluded: fresh).isEmpty)
    }

    @Test("An item added by hand lands where its day says")
    func insertsByDay() {
        let book = Self.draft(.brief)
        let assembler = BookAssembler(book: book, sources: Self.sources())
        let candidate = Self.sources().photos.first { photo in !book.items.contains(.photo(photo.id)) && photo.id != book.coverPhotoId }!
        var items = book.items
        assembler.insertByDay(&items, .photo(candidate.id))
        let at = items.firstIndex(of: .photo(candidate.id))!
        let day = BookDay.dayOf(candidate.photoDate)
        #expect(items[..<at].allSatisfy { (assembler.itemDay($0) ?? "") <= day })
        if at + 1 < items.count {
            #expect((assembler.itemDay(items[at + 1]) ?? "") > day)
        }
    }

    @Test("A save sends every category as none, and a subset in order")
    func normalisesCategories() {
        var book = Self.plan()
        book.categories = ["photos", "quotes", "artwork", "milestones"]
        #expect(book.content(reviewedAt: nil).categories == [])
        book.categories = ["quotes", "artwork"]
        #expect(book.content(reviewedAt: nil).categories == ["artwork", "quotes"])
    }

    @Test("Go's times parse with nanoseconds and offsets")
    func parsesServerTimes() {
        let plain = BookTime.parse("2026-06-02T00:00:00Z")
        #expect(plain != nil)
        #expect(BookTime.parse("2026-06-02T00:00:00.123456789Z") == plain)
        #expect(BookTime.parse("2026-06-01T19:00:00-05:00") == plain)
        #expect(BookTime.parse("") == nil)
    }

    // MARK: - Plans

    @Test("Titles follow the preset")
    func titles() {
        let year = BookPlans.calendarYear(2025)
        #expect(BookPlans.defaultTitle(preset: BookPreset.firstYear, names: ["Juniper"], period: year, yearKind: .calendar, age: 0) == "Juniper's first year")
        #expect(BookPlans.defaultTitle(preset: BookPreset.year, names: ["James"], period: year, yearKind: .calendar, age: 0) == "James' 2025")
        #expect(BookPlans.defaultTitle(preset: BookPreset.year, names: ["Theo"], period: year, yearKind: .age, age: 7) == "Theo at seven")
        #expect(BookPlans.defaultTitle(preset: BookPreset.year, names: ["Theo"], period: year, yearKind: .past, age: 0) == "Theo's year")
        #expect(BookPlans.defaultTitle(preset: BookPreset.familyYear, names: ["Ava", "Ben"], period: year, yearKind: .calendar, age: 0) == "Our 2025")
        let spring = BookPlans.Period(start: "2025-02-01", end: "2025-05-01")
        #expect(BookPlans.defaultTitle(preset: BookPreset.custom, names: ["Ava", "Ben"], period: spring, yearKind: .calendar, age: 0) == "Ava and Ben, February – April 2025")
    }

    @Test("Periods are half-open and concrete")
    func periods() {
        #expect(BookPlans.calendarYear(2025) == BookPlans.Period(start: "2025-01-01", end: "2026-01-01"))
        #expect(BookPlans.pastYear(today: "2026-10-01") == BookPlans.Period(start: "2025-10-02", end: "2026-10-02"))
        #expect(BookPlans.yearOfAge(birthday: "2021-06-01T00:00:00Z", age: 4) == BookPlans.Period(start: "2025-06-01", end: "2026-06-01"))
        #expect(BookPlans.firstYear(birthday: "2024-02-29T00:00:00Z") == BookPlans.Period(start: "2024-02-29", end: "2025-03-01"))
        #expect(BookPlans.ageNow(birthday: "2021-06-01T00:00:00Z", today: "2026-05-31") == 4)
    }

    @Test("Book write proc names match the backend")
    func procNames() {
        #expect(RPCMethod.getBookSources.rawValue == "GetBookSources")
        #expect(RPCMethod.createBook.rawValue == "CreateBook")
        #expect(RPCMethod.updateBook.rawValue == "UpdateBook")
        #expect(RPCMethod.deleteBook.rawValue == "DeleteBook")
    }

    @Test("An update sends the revision and the whole content")
    func encodesUpdate() throws {
        var book = Self.plan()
        book.items = [.photo(5), .milestone(2, photoId: 7)]
        let request = UpdateBookRequestDTO(id: 3, revision: 4, content: book.content(reviewedAt: "2026-10-01T12:00:00Z"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        #expect(object["revision"] as? Int == 4)
        let content = object["content"] as! [String: Any]
        #expect(content["reviewedAt"] as? String == "2026-10-01T12:00:00Z")
        let items = content["items"] as! [[String: Any]]
        #expect(items.map { $0["kind"] as? Int } == [1, 0])
        #expect(items[1]["photoId"] as? Int == 7)
        #expect(items[0]["key"] == nil)

        let create = CreateBookRequestDTO(personIds: [1], preset: "first-year", startDate: "2024-03-14", endDate: "2025-03-14", content: book.content(reviewedAt: nil))
        let createObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(create)) as! [String: Any]
        #expect((createObject["content"] as! [String: Any])["reviewedAt"] == nil)
    }
}

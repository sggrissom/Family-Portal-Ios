import Foundation

// Books (backend/book.go): `ListBooks` for the shelf and `GetBook` for one book with the records it draws on.
// Dates stay the server's own ISO strings rather than `Date`s. The reader is a port of `frontend/lib/book.ts`, which reads every date as the day its string names (`dayOf`), and a `Date` would bring the device's time zone back into a question the web answers without one.
// Every list is decoded leniently, since Go marshals a nil slice as `null`.

// MARK: - Requests

/// `familyId` 0 is the caller's primary family.
nonisolated struct ListBooksRequestDTO: Encodable, Sendable {
    let familyId: Int
}

nonisolated struct GetBookRequestDTO: Encodable, Sendable {
    let id: Int
}

// MARK: - The shelf

nonisolated struct BookSummaryDTO: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    @OrZero var personIds: [Int]
    @OrZero var personNames: [String]
    @OrZero var preset: String
    @OrZero var title: String
    @OrZero var startDate: String
    @OrZero var endDate: String
    /// 0 when there is no cover, or one the viewer may not see.
    @OrZero var coverPhotoId: Int
    @OrZero var updatedAt: String

    init(id: Int, personIds: [Int], personNames: [String], preset: String, title: String, startDate: String, endDate: String, coverPhotoId: Int, updatedAt: String) {
        self.id = id
        self.personIds = personIds
        self.personNames = personNames
        self.preset = preset
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.coverPhotoId = coverPhotoId
        self.updatedAt = updatedAt
    }
}

/// Newest-edited first, as the server sorts them. `canEdit` is whether the viewer may create and change books.
nonisolated struct ListBooksResponseDTO: Decodable, Sendable {
    @OrZero var books: [BookSummaryDTO]
    @OrZero var canEdit: Bool
}

// MARK: - One book

/// `BookItemKind`'s iota order in backend/book.go.
nonisolated enum BookItemKind: Int, Sendable {
    case milestone = 0
    case photo = 1
}

/// A reference to a source record. `photoId` pairs a milestone with one of its attached photos; `caption` overrides a photo's caption in this book only.
nonisolated struct BookItemDTO: Codable, Sendable, Hashable {
    /// Raw rather than `BookItemKind`: a kind added server-side is skipped by the reader instead of failing the whole book.
    @OrZero var kind: Int
    @OrZero var sourceId: Int
    @OrZero var photoId: Int
    @OrZero var caption: String
    /// Kept: stays when photos are picked again.
    @OrZero var pinned: Bool

    var itemKind: BookItemKind? { BookItemKind(rawValue: kind) }

    /// `itemKey`: one record, whatever its caption or photo.
    var key: String { "\(kind):\(sourceId)" }

    init(kind: BookItemKind, sourceId: Int, photoId: Int = 0, caption: String = "", pinned: Bool = false) {
        self.kind = kind.rawValue
        self.sourceId = sourceId
        self.photoId = photoId
        self.caption = caption
        self.pinned = pinned
    }
}

/// A saved book. `startDate`/`endDate` are half-open — `endDate` is the day after the last one covered — except that a first-year book also keeps its first birthday.
/// Mutable so the editor can work on a copy and assemble it as it goes.
nonisolated struct BookDTO: Decodable, Sendable {
    var id: Int
    @OrZero var personIds: [Int]
    @OrZero var preset: String
    @OrZero var title: String
    @OrZero var startDate: String
    @OrZero var endDate: String
    @OrZero var coverPhotoId: Int
    @OrZero var density: String
    /// Empty means every category.
    @OrZero var categories: [String]
    @OrZero var match: String
    @OrZero var introduction: String
    @OrZero var letter: String
    @OrZero var signature: String
    @OrZero var showGrowth: Bool
    @OrZero var items: [BookItemDTO]
    /// Records the editor took out, which a re-pick must never bring back.
    @OrZero var excluded: [BookItemDTO]
    @OrZero var revision: Int
    /// When the editor last looked at what the family record holds; anything created since is offered as new.
    @OrZero var reviewedAt: String

    init(
        id: Int = 1,
        personIds: [Int],
        preset: String,
        title: String,
        startDate: String,
        endDate: String,
        coverPhotoId: Int = 0,
        density: String = "balanced",
        categories: [String] = [],
        match: String = "any",
        introduction: String = "",
        letter: String = "",
        signature: String = "",
        showGrowth: Bool = true,
        items: [BookItemDTO],
        excluded: [BookItemDTO] = [],
        revision: Int = 1,
        reviewedAt: String = ""
    ) {
        self.id = id
        self.personIds = personIds
        self.preset = preset
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.coverPhotoId = coverPhotoId
        self.density = density
        self.categories = categories
        self.match = match
        self.introduction = introduction
        self.letter = letter
        self.signature = signature
        self.showGrowth = showGrowth
        self.items = items
        self.excluded = excluded
        self.revision = revision
        self.reviewedAt = reviewedAt
    }
}

nonisolated struct BookPersonDTO: Decodable, Sendable {
    let id: Int
    @OrZero var name: String
    @OrZero var birthday: String
    @OrZero var isPregnancy: Bool
    @OrZero var profilePhotoId: Int

    init(id: Int, name: String, birthday: String, isPregnancy: Bool = false, profilePhotoId: Int = 0) {
        self.id = id
        self.name = name
        self.birthday = birthday
        self.isPregnancy = isPregnancy
        self.profilePhotoId = profilePhotoId
    }
}

nonisolated struct BookMilestoneDTO: Decodable, Sendable {
    let id: Int
    @OrZero var personId: Int
    @OrZero var description: String
    @OrZero var category: String
    @OrZero var context: String
    @OrZero var milestoneDate: String
    @OrZero var createdAt: String
    @OrZero var photoIds: [Int]

    init(id: Int, personId: Int, description: String, category: String = "development", context: String = "", milestoneDate: String, createdAt: String? = nil, photoIds: [Int] = []) {
        self.id = id
        self.personId = personId
        self.description = description
        self.category = category
        self.context = context
        self.milestoneDate = milestoneDate
        self.createdAt = createdAt ?? milestoneDate
        self.photoIds = photoIds
    }
}

nonisolated struct BookImageDTO: Decodable, Sendable {
    let id: Int
    @OrZero var originalFilename: String
    @OrZero var width: Int
    @OrZero var height: Int
    @OrZero var title: String
    @OrZero var description: String
    @OrZero var photoDate: String
    @OrZero var createdAt: String
    /// 0 is ready; anything else is still processing or failed, and the reader leaves it out.
    @OrZero var status: Int

    init(id: Int, originalFilename: String = "photo.jpg", width: Int = 800, height: Int = 600, title: String = "", description: String = "", photoDate: String, createdAt: String? = nil, status: Int = 0) {
        self.id = id
        self.originalFilename = originalFilename
        self.width = width
        self.height = height
        self.title = title
        self.description = description
        self.photoDate = photoDate
        self.createdAt = createdAt ?? photoDate
        self.status = status
    }
}

nonisolated struct BookGrowthDTO: Decodable, Sendable {
    let id: Int
    @OrZero var personId: Int
    /// 0 height, 1 weight, as in every response.
    @OrZero var measurementType: Int
    @OrZero var value: Double
    @OrZero var unit: String
    @OrZero var measurementDate: String

    init(id: Int, personId: Int, measurementType: Int, value: Double, unit: String, measurementDate: String) {
        self.id = id
        self.personId = personId
        self.measurementType = measurementType
        self.value = value
        self.unit = unit
        self.measurementDate = measurementDate
    }
}

/// The records a book may draw on, already filtered by the server to what the viewer may see. `photoPeople` says which of the book's people each photo is tagged with; its keys are photo ids, as strings because JSON object keys are.
nonisolated struct BookSourcesDTO: Decodable, Sendable {
    let people: [BookPersonDTO]
    let milestones: [BookMilestoneDTO]
    let photos: [BookImageDTO]
    let growthData: [BookGrowthDTO]
    let photoPeople: [Int: [Int]]
    let untagged: [Int]

    private enum CodingKeys: String, CodingKey { case people, milestones, photos, growthData, photoPeople, untagged }

    init(people: [BookPersonDTO], milestones: [BookMilestoneDTO] = [], photos: [BookImageDTO] = [], growthData: [BookGrowthDTO] = [], photoPeople: [Int: [Int]] = [:], untagged: [Int] = []) {
        self.people = people
        self.milestones = milestones
        self.photos = photos
        self.growthData = growthData
        self.photoPeople = photoPeople
        self.untagged = untagged
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        people = try c.decodeList(BookPersonDTO.self, forKey: .people)
        milestones = try c.decodeList(BookMilestoneDTO.self, forKey: .milestones)
        photos = try c.decodeList(BookImageDTO.self, forKey: .photos)
        growthData = try c.decodeList(BookGrowthDTO.self, forKey: .growthData)
        let raw = try c.decodeIfPresent([String: [Int]?].self, forKey: .photoPeople) ?? [:]
        var photoPeople: [Int: [Int]] = [:]
        for (key, people) in raw {
            if let id = Int(key) { photoPeople[id] = people ?? [] }
        }
        self.photoPeople = photoPeople
        untagged = try c.decodeList(Int.self, forKey: .untagged)
    }
}

nonisolated struct GetBookResponseDTO: Decodable, Sendable, Identifiable {
    var id: Int { book.id }

    let book: BookDTO
    let sources: BookSourcesDTO
    @OrZero var canEdit: Bool
    /// The server's clock when it answered, which a save sends back as `reviewedAt`: the device's clock is not the one `createdAt` was stamped with.
    @OrZero var now: String
}

// MARK: - Writes

/// The records a new book could draw on, with the concrete dates the server settled for it.
nonisolated struct GetBookSourcesRequestDTO: Encodable, Sendable {
    let personIds: [Int]
    let preset: String
    /// `YYYY-MM-DD`; ignored for a first year, which the birthday decides.
    let startDate: String
    let endDate: String
}

nonisolated struct GetBookSourcesResponseDTO: Decodable, Sendable {
    let sources: BookSourcesDTO
    @OrZero var startDate: String
    @OrZero var endDate: String
}

/// Everything about a book the editor can change. The whole thing is sent on every save; the server checks every reference against the book's people and the editor's access.
nonisolated struct BookContentDTO: Encodable, Sendable, Equatable {
    let title: String
    let coverPhotoId: Int
    let density: String
    let categories: [String]
    let match: String
    let introduction: String
    let letter: String
    let signature: String
    let showGrowth: Bool
    let items: [BookItemDTO]
    let excluded: [BookItemDTO]
    /// An ISO time, or omitted: Go cannot parse an empty string as a `time.Time`.
    let reviewedAt: String?
}

nonisolated extension BookDTO {
    /// What a save sends. Every category chosen is sent as none, the server's "everything", so a book keeps picking up a kind of content added later.
    func content(reviewedAt: String?) -> BookContentDTO {
        BookContentDTO(
            title: title,
            coverPhotoId: coverPhotoId,
            density: density,
            categories: Set(categories).count >= 4 ? [] : categories.sorted(),
            match: match,
            introduction: introduction,
            letter: letter,
            signature: signature,
            showGrowth: showGrowth,
            items: items,
            excluded: excluded,
            reviewedAt: reviewedAt
        )
    }
}

nonisolated struct CreateBookRequestDTO: Encodable, Sendable {
    let personIds: [Int]
    let preset: String
    let startDate: String
    let endDate: String
    let content: BookContentDTO
}

/// `revision` is the one the editor opened; a save over someone else's is refused (`BookService.changedMessage`).
nonisolated struct UpdateBookRequestDTO: Encodable, Sendable {
    let id: Int
    let revision: Int
    let content: BookContentDTO
}

nonisolated struct DeleteBookRequestDTO: Encodable, Sendable {
    let id: Int
}

nonisolated struct BookResponseDTO: Decodable, Sendable {
    let book: BookDTO
}

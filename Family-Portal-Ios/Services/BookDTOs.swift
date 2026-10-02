import Foundation

// Books (backend/book.go): `ListBooks` for the shelf and `GetBook` for one book with the records it draws on.
// Dates stay the server's own ISO strings rather than `Date`s. The reader is a port of `frontend/lib/book.ts`, which reads every date as the day its string names (`dayOf`), and a `Date` would bring the device's time zone back into a question the web answers without one.
// Every list is decoded leniently, since Go marshals a nil slice as `null`.

fileprivate extension KeyedDecodingContainer {
    nonisolated func decodeText(forKey key: Key) throws -> String {
        try decodeIfPresent(String.self, forKey: key) ?? ""
    }

    nonisolated func decodeNumber(forKey key: Key) throws -> Int {
        try decodeIfPresent(Int.self, forKey: key) ?? 0
    }
}

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
    let personIds: [Int]
    let personNames: [String]
    let preset: String
    let title: String
    let startDate: String
    let endDate: String
    /// 0 when there is no cover, or one the viewer may not see.
    let coverPhotoId: Int
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, personIds, personNames, preset, title, startDate, endDate, coverPhotoId, updatedAt
    }

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        personIds = try c.decodeList(Int.self, forKey: .personIds)
        personNames = try c.decodeList(String.self, forKey: .personNames)
        preset = try c.decodeText(forKey: .preset)
        title = try c.decodeText(forKey: .title)
        startDate = try c.decodeText(forKey: .startDate)
        endDate = try c.decodeText(forKey: .endDate)
        coverPhotoId = try c.decodeNumber(forKey: .coverPhotoId)
        updatedAt = try c.decodeText(forKey: .updatedAt)
    }
}

/// Newest-edited first, as the server sorts them. `canEdit` is whether the viewer may create and change books.
nonisolated struct ListBooksResponseDTO: Decodable, Sendable {
    let books: [BookSummaryDTO]
    let canEdit: Bool

    private enum CodingKeys: String, CodingKey { case books, canEdit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        books = try c.decodeList(BookSummaryDTO.self, forKey: .books)
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
    }
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
    var kind: Int
    var sourceId: Int
    var photoId: Int
    var caption: String
    /// Kept: stays when photos are picked again.
    var pinned: Bool

    var itemKind: BookItemKind? { BookItemKind(rawValue: kind) }

    /// `itemKey`: one record, whatever its caption or photo.
    var key: String { "\(kind):\(sourceId)" }

    private enum CodingKeys: String, CodingKey { case kind, sourceId, photoId, caption, pinned }

    init(kind: BookItemKind, sourceId: Int, photoId: Int = 0, caption: String = "", pinned: Bool = false) {
        self.kind = kind.rawValue
        self.sourceId = sourceId
        self.photoId = photoId
        self.caption = caption
        self.pinned = pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeNumber(forKey: .kind)
        sourceId = try c.decodeNumber(forKey: .sourceId)
        photoId = try c.decodeNumber(forKey: .photoId)
        caption = try c.decodeText(forKey: .caption)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

/// A saved book. `startDate`/`endDate` are half-open — `endDate` is the day after the last one covered — except that a first-year book also keeps its first birthday.
/// Mutable so the editor can work on a copy and assemble it as it goes.
nonisolated struct BookDTO: Decodable, Sendable {
    var id: Int
    var personIds: [Int]
    var preset: String
    var title: String
    var startDate: String
    var endDate: String
    var coverPhotoId: Int
    var density: String
    /// Empty means every category.
    var categories: [String]
    var match: String
    var introduction: String
    var letter: String
    var signature: String
    var showGrowth: Bool
    var items: [BookItemDTO]
    /// Records the editor took out, which a re-pick must never bring back.
    var excluded: [BookItemDTO]
    var revision: Int
    /// When the editor last looked at what the family record holds; anything created since is offered as new.
    var reviewedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, personIds, preset, title, startDate, endDate, coverPhotoId, density, categories, match
        case introduction, letter, signature, showGrowth, items, excluded, revision, reviewedAt
    }

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        personIds = try c.decodeList(Int.self, forKey: .personIds)
        preset = try c.decodeText(forKey: .preset)
        title = try c.decodeText(forKey: .title)
        startDate = try c.decodeText(forKey: .startDate)
        endDate = try c.decodeText(forKey: .endDate)
        coverPhotoId = try c.decodeNumber(forKey: .coverPhotoId)
        density = try c.decodeText(forKey: .density)
        categories = try c.decodeList(String.self, forKey: .categories)
        match = try c.decodeText(forKey: .match)
        introduction = try c.decodeText(forKey: .introduction)
        letter = try c.decodeText(forKey: .letter)
        signature = try c.decodeText(forKey: .signature)
        showGrowth = try c.decodeIfPresent(Bool.self, forKey: .showGrowth) ?? false
        items = try c.decodeList(BookItemDTO.self, forKey: .items)
        excluded = try c.decodeList(BookItemDTO.self, forKey: .excluded)
        revision = try c.decodeNumber(forKey: .revision)
        reviewedAt = try c.decodeText(forKey: .reviewedAt)
    }
}

nonisolated struct BookPersonDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let birthday: String
    let isPregnancy: Bool
    let profilePhotoId: Int

    private enum CodingKeys: String, CodingKey { case id, name, birthday, isPregnancy, profilePhotoId }

    init(id: Int, name: String, birthday: String, isPregnancy: Bool = false, profilePhotoId: Int = 0) {
        self.id = id
        self.name = name
        self.birthday = birthday
        self.isPregnancy = isPregnancy
        self.profilePhotoId = profilePhotoId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeText(forKey: .name)
        birthday = try c.decodeText(forKey: .birthday)
        isPregnancy = try c.decodeIfPresent(Bool.self, forKey: .isPregnancy) ?? false
        profilePhotoId = try c.decodeNumber(forKey: .profilePhotoId)
    }
}

nonisolated struct BookMilestoneDTO: Decodable, Sendable {
    let id: Int
    let personId: Int
    let description: String
    let category: String
    let context: String
    let milestoneDate: String
    let createdAt: String
    let photoIds: [Int]

    private enum CodingKeys: String, CodingKey { case id, personId, description, category, context, milestoneDate, createdAt, photoIds }

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        personId = try c.decodeNumber(forKey: .personId)
        description = try c.decodeText(forKey: .description)
        category = try c.decodeText(forKey: .category)
        context = try c.decodeText(forKey: .context)
        milestoneDate = try c.decodeText(forKey: .milestoneDate)
        createdAt = try c.decodeText(forKey: .createdAt)
        photoIds = try c.decodeList(Int.self, forKey: .photoIds)
    }
}

nonisolated struct BookImageDTO: Decodable, Sendable {
    let id: Int
    let originalFilename: String
    let width: Int
    let height: Int
    let title: String
    let description: String
    let photoDate: String
    let createdAt: String
    /// 0 is ready; anything else is still processing or failed, and the reader leaves it out.
    let status: Int

    private enum CodingKeys: String, CodingKey { case id, originalFilename, width, height, title, description, photoDate, createdAt, status }

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        originalFilename = try c.decodeText(forKey: .originalFilename)
        width = try c.decodeNumber(forKey: .width)
        height = try c.decodeNumber(forKey: .height)
        title = try c.decodeText(forKey: .title)
        description = try c.decodeText(forKey: .description)
        photoDate = try c.decodeText(forKey: .photoDate)
        createdAt = try c.decodeText(forKey: .createdAt)
        status = try c.decodeNumber(forKey: .status)
    }
}

nonisolated struct BookGrowthDTO: Decodable, Sendable {
    let id: Int
    let personId: Int
    /// 0 height, 1 weight, as in every response.
    let measurementType: Int
    let value: Double
    let unit: String
    let measurementDate: String

    private enum CodingKeys: String, CodingKey { case id, personId, measurementType, value, unit, measurementDate }

    init(id: Int, personId: Int, measurementType: Int, value: Double, unit: String, measurementDate: String) {
        self.id = id
        self.personId = personId
        self.measurementType = measurementType
        self.value = value
        self.unit = unit
        self.measurementDate = measurementDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        personId = try c.decodeNumber(forKey: .personId)
        measurementType = try c.decodeNumber(forKey: .measurementType)
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
        unit = try c.decodeText(forKey: .unit)
        measurementDate = try c.decodeText(forKey: .measurementDate)
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
    let canEdit: Bool
    /// The server's clock when it answered, which a save sends back as `reviewedAt`: the device's clock is not the one `createdAt` was stamped with.
    let now: String

    private enum CodingKeys: String, CodingKey { case book, sources, canEdit, now }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        book = try c.decode(BookDTO.self, forKey: .book)
        sources = try c.decode(BookSourcesDTO.self, forKey: .sources)
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        now = try c.decodeText(forKey: .now)
    }
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
    let startDate: String
    let endDate: String

    private enum CodingKeys: String, CodingKey { case sources, startDate, endDate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decode(BookSourcesDTO.self, forKey: .sources)
        startDate = try c.decodeText(forKey: .startDate)
        endDate = try c.decodeText(forKey: .endDate)
    }
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

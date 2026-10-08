import Foundation

// The offline-analysis reads (backend/milestone_analysis.go and friends). Every one is an online read the app never queues: the vision daemon runs only on staging, so each proc degrades to an empty answer rather than failing, and the screens that use them must look normal with nothing to show.
// Every list is decoded with `decodeList`, since Go marshals a nil slice as `null`.

// MARK: - Milestone suggestions

nonisolated struct SuggestMilestoneCategoryRequestDTO: Encodable, Sendable {
    let description: String
    /// 0 when nobody is picked yet; the server then compares against the caller's own family.
    let personId: Int
}

nonisolated struct SuggestMilestoneCategoryResponseDTO: Decodable, Sendable {
    /// Empty when there is no suggestion.
    let category: String

    private enum CodingKeys: String, CodingKey { case category }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
    }
}

nonisolated struct SuggestMilestonePhotosRequestDTO: Encodable, Sendable {
    let personId: Int
    let description: String
    let inputType: String        // always "date"
    let milestoneDate: String    // "yyyy-MM-dd"
    let excludeIds: [Int]
}

/// At most eight photos of the person from about two weeks either side of the date, best match first.
nonisolated struct SuggestMilestonePhotosResponseDTO: Decodable, Sendable {
    let photoIds: [Int]
    /// False when the photos are only the nearest by date, because the description could not be compared.
    let ranked: Bool

    private enum CodingKeys: String, CodingKey { case photoIds, ranked }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photoIds = try c.decodeList(Int.self, forKey: .photoIds)
        ranked = try c.decodeIfPresent(Bool.self, forKey: .ranked) ?? false
    }
}

// MARK: - Milestone matches

nonisolated struct GetMilestoneMatchesRequestDTO: Encodable, Sendable {
    let milestoneId: Int
}

/// The same milestone in a sibling's or cousin's life, however it was worded.
nonisolated struct MilestoneMatchDTO: Decodable, Sendable {
    let person: PersonDTO
    let milestone: MilestoneDTO
    /// -1 when that person has no birthday.
    let ageMonths: Int
}

nonisolated struct GetMilestoneMatchesResponseDTO: Decodable, Sendable {
    /// The asked-about milestone's own age, -1 without a birthday.
    let ageMonths: Int
    let matches: [MilestoneMatchDTO]

    private enum CodingKeys: String, CodingKey { case ageMonths, matches }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ageMonths = try c.decodeIfPresent(Int.self, forKey: .ageMonths) ?? -1
        matches = try c.decodeList(MilestoneMatchDTO.self, forKey: .matches)
    }
}

// MARK: - Person photo insights (backend/person_photo_insights.go)
// Built on face data rather than the vision daemon, so these work in production too.

/// A face's box within its photo, each edge a fraction of the photo's width or height.
nonisolated struct FaceBoxDTO: Codable, Sendable, Equatable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    /// Face analysis found nothing when the box is empty; the server sends it zeroed rather than absent.
    var hasArea: Bool {
        right > left && bottom > top
    }
}

/// A photo chosen to show the person, with their face box when face analysis found one.
nonisolated struct PortraitPhotoDTO: Decodable, Sendable {
    let photoId: Int
    let box: FaceBoxDTO
    let date: Date
    /// The month under two, the year (in months) after, or -1 without a birthday.
    let ageMonths: Int
    let year: Int
}

nonisolated struct OftenWithDTO: Decodable, Sendable {
    let person: PersonDTO
    let count: Int
    let lastDate: Date
}

nonisolated struct GetPersonPhotoInsightsRequestDTO: Encodable, Sendable {
    let personId: Int
}

nonisolated struct GetPersonPhotoInsightsResponseDTO: Decodable, Sendable {
    let growingUp: [PortraitPhotoDTO]
    let oftenWith: [OftenWithDTO]
    /// A face to show in place of the initials when the person has no profile photo. A suggestion only; never stored.
    let header: PortraitPhotoDTO?

    private enum CodingKeys: String, CodingKey { case growingUp, oftenWith, header }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        growingUp = try c.decodeList(PortraitPhotoDTO.self, forKey: .growingUp)
        oftenWith = try c.decodeList(OftenWithDTO.self, forKey: .oftenWith)
        header = try c.decodeIfPresent(PortraitPhotoDTO.self, forKey: .header)
    }

    /// The label under a growing-up face: the age, or the year for someone with no birthday.
    static func label(for portrait: PortraitPhotoDTO) -> String {
        portrait.ageMonths < 0 ? String(portrait.year) : AgeSteps.ageTitle(portrait.ageMonths)
    }
}

// MARK: - Photos: place and tag suggestions (backend/places.go, backend/tag_suggestions.go)

nonisolated struct PhotoPlaceDTO: Decodable, Sendable {
    /// `f<id>` for a place the family named, `c<id>` for a city. What `ListFamilyPhotos`' `placeKey` filters on.
    let key: String
    let name: String
    let familyPlaceId: Int
    let latitude: Double
    let longitude: Double
}

/// A pending suggestion on one photo, as the photo page shows it.
nonisolated struct SuggestedTagDTO: Decodable, Sendable, Identifiable {
    /// A **suggestion** id, which is what accept and reject take — never a tag id.
    let id: Int
    let label: String
    let color: String

    private enum CodingKeys: String, CodingKey { case id, label, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
    }
}

/// `AcceptTagSuggestions` and `RejectTagSuggestions`. Suggestion ids, not tag ids.
nonisolated struct SuggestionIdsRequestDTO: Encodable, Sendable {
    let ids: [Int]
}

nonisolated struct SuggestionIdsResponseDTO: Decodable, Sendable {
    let updated: Int

    private enum CodingKeys: String, CodingKey { case updated }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updated = try c.decodeIfPresent(Int.self, forKey: .updated) ?? 0
    }
}

/// One suggestion in the review, with the photo it is about.
nonisolated struct TagSuggestionDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let photoId: Int
    let familyId: Int
    /// 0 until a catalog label is first accepted and becomes a family tag.
    let tagId: Int
    let label: String
    let score: Double
}

/// Every pending suggestion for one tag or catalog label, best first.
nonisolated struct SuggestionGroupDTO: Decodable, Sendable, Identifiable {
    let key: String
    let label: String
    let tagId: Int
    let color: String
    let familyId: Int
    let suggestions: [TagSuggestionDTO]

    var id: String { key }

    private enum CodingKeys: String, CodingKey { case key, label, tagId, color, familyId, suggestions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        tagId = try c.decodeIfPresent(Int.self, forKey: .tagId) ?? 0
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        familyId = try c.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        suggestions = try c.decodeList(TagSuggestionDTO.self, forKey: .suggestions)
    }
}

nonisolated struct GetTagSuggestionsResponseDTO: Decodable, Sendable {
    /// False where photo analysis isn't running at all, as opposed to having nothing to suggest.
    let enabled: Bool
    let groups: [SuggestionGroupDTO]
    let total: Int

    private enum CodingKeys: String, CodingKey { case enabled, groups, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        groups = try c.decodeList(SuggestionGroupDTO.self, forKey: .groups)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
    }

    /// The review is worth a link only when there is something in it.
    var hasSuggestions: Bool {
        enabled && total > 0
    }
}

/// One place in `ListPhotoPlaces`: the family's own named places first, then cities, by photo count.
nonisolated struct PhotoPlaceCountDTO: Decodable, Sendable, Identifiable, Equatable {
    let key: String
    let name: String
    let count: Int

    var id: String { key }

    /// A place the family named, rather than a city.
    var isFamilyPlace: Bool { key.hasPrefix("f") }

    private enum CodingKeys: String, CodingKey { case key, name, count }

    init(key: String, name: String, count: Int) {
        self.key = key
        self.name = name
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

nonisolated struct ListPhotoPlacesResponseDTO: Decodable, Sendable {
    let places: [PhotoPlaceCountDTO]

    private enum CodingKeys: String, CodingKey { case places }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        places = try c.decodeList(PhotoPlaceCountDTO.self, forKey: .places)
    }
}

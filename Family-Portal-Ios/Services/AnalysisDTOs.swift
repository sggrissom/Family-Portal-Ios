import Foundation

// The offline-analysis reads (backend/milestone_analysis.go and friends). Every one is an online read the app never queues: the vision daemon runs only on staging, so each proc degrades to an empty answer rather than failing, and the screens that use them must look normal with nothing to show.
// Every list is decoded with `decodeList`, since Go marshals a nil slice as `null`.

/// The same helper `OverviewDTOs.swift` keeps to itself.
fileprivate extension KeyedDecodingContainer {
    nonisolated func decodeList<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent([T].self, forKey: key) ?? []
    }
}

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

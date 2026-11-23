import Foundation

// The public family page (backend/family_page.go): one snapshot per family at
// /f/<slug>. Online only, never queued or cached.

nonisolated struct FamilyPageMemberSettingsDTO: Codable, Sendable, Equatable {
    var personId: Int
    var name: String
    var line: String
    var showAge: Bool
    var showPhoto: Bool
}

nonisolated struct FamilyPageSettingsDTO: Codable, Sendable, Equatable {
    var slug: String
    var indexable: Bool
    var title: String
    var intro: String
    var members: [FamilyPageMemberSettingsDTO]
    var photoIds: [Int]

    init(
        slug: String = "",
        indexable: Bool = false,
        title: String = "",
        intro: String = "",
        members: [FamilyPageMemberSettingsDTO] = [],
        photoIds: [Int] = []
    ) {
        self.slug = slug
        self.indexable = indexable
        self.title = title
        self.intro = intro
        self.members = members
        self.photoIds = photoIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decodeOrZero(forKey: .slug)
        indexable = try c.decodeOrZero(forKey: .indexable)
        title = try c.decodeOrZero(forKey: .title)
        intro = try c.decodeOrZero(forKey: .intro)
        members = try c.decodeList(FamilyPageMemberSettingsDTO.self, forKey: .members)
        photoIds = try c.decodeList(Int.self, forKey: .photoIds)
    }
}

/// Someone on the family's roster the editor can add. `ageYears` is nil for a pregnancy or a missing birthday; `profilePhotoId` is 0 when there is no usable profile photo.
nonisolated struct FamilyPagePersonDTO: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    var ageYears: Int? = nil
    @OrZero var profilePhotoId: Int
    @OrZero var profileCropX: Double
    @OrZero var profileCropY: Double
    @OrZero var profileCropScale: Double
}

nonisolated struct FamilyPageSettingsResponseDTO: Decodable, Sendable {
    let familyId: Int
    let canEdit: Bool
    let published: Bool
    @OrZero var url: String
    var publishedAt: Date? = nil
    @OrZero var publishedByName: String
    let settings: FamilyPageSettingsDTO
    @OrZero var people: [FamilyPagePersonDTO]
}

nonisolated struct PublishFamilyPageRequestDTO: Encodable, Sendable {
    let familyId: Int
    let settings: FamilyPageSettingsDTO
}

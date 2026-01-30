@preconcurrency import Foundation

struct AuthResponseDTO: Sendable {
    let id: Int
    let name: String
    let email: String
    let isAdmin: Bool
    let familyId: Int?

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        isAdmin = try container.decode(Bool.self, forKey: .isAdmin)
        familyId = try container.decodeIfPresent(Int.self, forKey: .familyId)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(email, forKey: .email)
        try container.encode(isAdmin, forKey: .isAdmin)
        try container.encodeIfPresent(familyId, forKey: .familyId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email, isAdmin, familyId
    }
}

extension AuthResponseDTO: Codable {}

struct LoginResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let token: String?
    let auth: AuthResponseDTO?
}

struct RefreshResponseDTO: Sendable {
    let success: Bool
    let error: String?
    let token: String?
    let auth: AuthResponseDTO?

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        auth = try container.decodeIfPresent(AuthResponseDTO.self, forKey: .auth)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(token, forKey: .token)
        try container.encodeIfPresent(auth, forKey: .auth)
    }

    private enum CodingKeys: String, CodingKey {
        case success, error, token, auth
    }
}

extension RefreshResponseDTO: Codable {}

struct FamilyInfoDTO: Codable, Sendable {
    let id: Int
    let name: String
    let inviteCode: String
}

struct PersonDTO: Codable, Sendable {
    let id: Int
    let familyId: Int
    let name: String
    let type: Int
    let gender: Int
    let birthday: Date
    let age: String
    let profilePhotoId: Int?
    let profileCropX: Double?
    let profileCropY: Double?
    let profileCropScale: Double?
}

struct GrowthDataDTO: Codable, Sendable {
    let id: Int
    let personId: Int
    let familyId: Int
    let measurementType: Int
    let value: Double
    let unit: String
    let measurementDate: Date
    let createdAt: Date
}

struct MilestoneDTO: Codable, Sendable {
    let id: Int
    let personId: Int
    let familyId: Int
    let descriptionText: String
    let category: String
    let milestoneDate: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case personId
        case familyId
        case descriptionText = "description"
        case category
        case milestoneDate
        case createdAt
    }
}

struct ImageDTO: Codable, Sendable {
    let id: Int
    let familyId: Int
    let ownerUserId: Int
    let originalFilename: String
    let mimeType: String
    let fileSize: Int
    let width: Int
    let height: Int
    let filePath: String
    let title: String
    let descriptionText: String
    let photoDate: Date
    let createdAt: Date
    let status: Int

    enum CodingKeys: String, CodingKey {
        case id
        case familyId
        case ownerUserId
        case originalFilename
        case mimeType
        case fileSize
        case width
        case height
        case filePath
        case title
        case descriptionText = "description"
        case photoDate
        case createdAt
        case status
    }
}

struct PhotoWithPeopleDTO: Codable, Sendable {
    let image: ImageDTO
    let people: [PersonDTO]
}

struct GetPersonResponseDTO: Codable, Sendable {
    let person: PersonDTO?
    let growthData: [GrowthDataDTO]
    let milestones: [MilestoneDTO]
    let photos: [ImageDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        person = try container.decodeIfPresent(PersonDTO.self, forKey: .person)
        growthData = try container.decodeIfPresent([GrowthDataDTO].self, forKey: .growthData) ?? []
        milestones = try container.decodeIfPresent([MilestoneDTO].self, forKey: .milestones) ?? []
        photos = try container.decodeIfPresent([ImageDTO].self, forKey: .photos) ?? []
    }
}

struct ListPeopleResponseDTO: Codable, Sendable {
    let people: [PersonDTO]
}

struct AddGrowthDataResponseDTO: Codable, Sendable {
    let growthData: GrowthDataDTO
}

struct UpdateGrowthDataResponseDTO: Codable, Sendable {
    let growthData: GrowthDataDTO
}

struct AddMilestoneResponseDTO: Codable, Sendable {
    let milestone: MilestoneDTO
}

struct UpdateMilestoneResponseDTO: Codable, Sendable {
    let milestone: MilestoneDTO
}

struct AddPhotoResponseDTO: Codable, Sendable {
    let image: ImageDTO
}

struct GetPhotoResponseDTO: Codable, Sendable {
    let image: ImageDTO
    let people: [PersonDTO]
}

struct ListFamilyPhotosResponseDTO: Codable, Sendable {
    let photos: [PhotoWithPeopleDTO]
}

struct FamilyTimelineItemDTO: Codable, Sendable {
    let person: PersonDTO
    let growthData: [GrowthDataDTO]
    let milestones: [MilestoneDTO]
    let photos: [ImageDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        person = try container.decode(PersonDTO.self, forKey: .person)
        growthData = try container.decodeIfPresent([GrowthDataDTO].self, forKey: .growthData) ?? []
        milestones = try container.decodeIfPresent([MilestoneDTO].self, forKey: .milestones) ?? []
        photos = try container.decodeIfPresent([ImageDTO].self, forKey: .photos) ?? []
    }
}

struct GetFamilyTimelineResponseDTO: Codable, Sendable {
    let people: [FamilyTimelineItemDTO]
}

// MARK: - Request DTOs

struct GoogleTokenLoginRequestDTO: Encodable, Sendable {
    let idToken: String
}

struct AddPersonRequestDTO: Encodable, Sendable {
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String  // "yyyy-MM-dd"
}

struct UpdatePersonRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String  // "yyyy-MM-dd"
}

struct AddGrowthDataRequestDTO: Encodable, Sendable {
    let personId: Int
    let measurementType: String  // "height" or "weight"
    let value: Double
    let unit: String             // "cm", "in", "kg", "lbs"
    let inputType: String        // "date" or "today"
    let measurementDate: String? // "yyyy-MM-dd" if inputType="date"
}

struct UpdateGrowthDataRequestDTO: Encodable, Sendable {
    let id: Int
    let measurementType: String
    let value: Double
    let unit: String
    let inputType: String
    let measurementDate: String?
}

struct DeleteRequestDTO: Encodable, Sendable {
    let id: Int
}

struct SuccessResponseDTO: Decodable, Sendable {
    let success: Bool
}

struct AddMilestoneRequestDTO: Encodable, Sendable {
    let personId: Int
    let description: String
    let category: String
    let inputType: String        // "date" or "today"
    let milestoneDate: String?   // "yyyy-MM-dd" if inputType="date"
}

struct UpdateMilestoneRequestDTO: Encodable, Sendable {
    let id: Int
    let description: String
    let category: String
    let inputType: String
    let milestoneDate: String?
}

struct AddPeopleToPhotoRequestDTO: Encodable, Sendable {
    let photoId: Int
    let personIds: [Int]
}

struct RemovePersonFromPhotoRequestDTO: Encodable, Sendable {
    let photoId: Int
    let personId: Int
}

struct AddPersonResponseDTO: Decodable, Sendable {
    let person: PersonDTO
    let growthData: [GrowthDataDTO]
    let milestones: [MilestoneDTO]
    let photos: [ImageDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        person = try container.decode(PersonDTO.self, forKey: .person)
        growthData = try container.decodeIfPresent([GrowthDataDTO].self, forKey: .growthData) ?? []
        milestones = try container.decodeIfPresent([MilestoneDTO].self, forKey: .milestones) ?? []
        photos = try container.decodeIfPresent([ImageDTO].self, forKey: .photos) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case person, growthData, milestones, photos
    }
}

struct UpdatePersonResponseDTO: Decodable, Sendable {
    let person: PersonDTO
}

import Foundation

struct AuthResponseDTO: Codable {
    let id: Int
    let name: String
    let email: String
    let isAdmin: Bool
    let familyId: Int?
}

struct LoginResponseDTO: Codable {
    let success: Bool
    let error: String?
    let token: String?
    let auth: AuthResponseDTO?
}

struct RefreshResponseDTO: Codable {
    let success: Bool
    let error: String?
    let token: String?
    let auth: AuthResponseDTO?
}

struct FamilyInfoDTO: Codable {
    let id: Int
    let name: String
    let inviteCode: String
}

struct PersonDTO: Codable {
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

struct GrowthDataDTO: Codable {
    let id: Int
    let personId: Int
    let familyId: Int
    let measurementType: Int
    let value: Double
    let unit: String
    let measurementDate: Date
    let createdAt: Date
}

struct MilestoneDTO: Codable {
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

struct ImageDTO: Codable {
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

struct PhotoWithPeopleDTO: Codable {
    let image: ImageDTO
    let people: [PersonDTO]
}

struct GetPersonResponseDTO: Codable {
    let person: PersonDTO?
    let growthData: [GrowthDataDTO]
    let milestones: [MilestoneDTO]
    let photos: [ImageDTO]
}

struct ListPeopleResponseDTO: Codable {
    let people: [PersonDTO]
}

struct AddGrowthDataResponseDTO: Codable {
    let growthData: GrowthDataDTO
}

struct UpdateGrowthDataResponseDTO: Codable {
    let growthData: GrowthDataDTO
}

struct AddMilestoneResponseDTO: Codable {
    let milestone: MilestoneDTO
}

struct UpdateMilestoneResponseDTO: Codable {
    let milestone: MilestoneDTO
}

struct GetPhotoResponseDTO: Codable {
    let image: ImageDTO
    let people: [PersonDTO]
}

struct ListFamilyPhotosResponseDTO: Codable {
    let photos: [PhotoWithPeopleDTO]
}

struct FamilyTimelineItemDTO: Codable {
    let person: PersonDTO
    let growthData: [GrowthDataDTO]
    let milestones: [MilestoneDTO]
    let photos: [ImageDTO]
}

struct GetFamilyTimelineResponseDTO: Codable {
    let people: [FamilyTimelineItemDTO]
}

// MARK: - Request DTOs

struct AddPersonRequestDTO: Encodable {
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String  // "yyyy-MM-dd"
}

struct AddGrowthDataRequestDTO: Encodable {
    let personId: Int
    let measurementType: String  // "height" or "weight"
    let value: Double
    let unit: String             // "cm", "in", "kg", "lbs"
    let inputType: String        // "date" or "today"
    let measurementDate: String? // "yyyy-MM-dd" if inputType="date"
}

struct UpdateGrowthDataRequestDTO: Encodable {
    let id: Int
    let measurementType: String
    let value: Double
    let unit: String
    let inputType: String
    let measurementDate: String?
}

struct DeleteRequestDTO: Encodable {
    let id: Int
}

struct SuccessResponseDTO: Decodable {
    let success: Bool
}

struct AddMilestoneRequestDTO: Encodable {
    let personId: Int
    let description: String
    let category: String
    let inputType: String        // "date" or "today"
    let milestoneDate: String?   // "yyyy-MM-dd" if inputType="date"
}

struct UpdateMilestoneRequestDTO: Encodable {
    let id: Int
    let description: String
    let category: String
    let inputType: String
    let milestoneDate: String?
}

struct AddPeopleToPhotoRequestDTO: Encodable {
    let photoId: Int
    let personIds: [Int]
}

struct RemovePersonFromPhotoRequestDTO: Encodable {
    let photoId: Int
    let personId: Int
}

struct AddPersonResponseDTO: Decodable {
    let person: PersonDTO
    let growthData: [GrowthDataDTO]
    let milestones: [MilestoneDTO]
    let photos: [ImageDTO]
}

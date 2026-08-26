@preconcurrency import Foundation

nonisolated struct AuthResponseDTO: Sendable {
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

nonisolated struct LoginResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let token: String?
    let auth: AuthResponseDTO?
}

nonisolated struct CreateAccountRequestDTO: Codable, Sendable {
    let name: String
    let email: String
    let password: String
    let confirmPassword: String
    let familyCode: String
    let initialPersonName: String
    let initialPersonGender: Int
    let initialPersonBirthdate: String
}

nonisolated struct CreateAccountResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let token: String?
    let auth: AuthResponseDTO?
}

nonisolated struct RequestPasswordResetRequestDTO: Codable, Sendable {
    let email: String
}

nonisolated struct RequestPasswordResetResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
}

/// `DeleteAccountRequest` in backend/account_deletion.go. `password` is empty for a Google-only account, where `confirmEmail` carries the whole weight.
nonisolated struct DeleteAccountRequestDTO: Codable, Sendable {
    let password: String
    let confirmEmail: String
}

nonisolated struct DeleteAccountResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
}

nonisolated struct RefreshResponseDTO: Sendable {
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

nonisolated struct MobileVersionPolicyDTO: Codable, Sendable {
    let status: String
    let minimumVersion: String
    let latestVersion: String
    let updateUrl: String
    let updateMessage: String
}

nonisolated struct FamilyInfoDTO: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let inviteCode: String
    let role: Int
    let isPrimary: Bool

    init(id: Int, name: String, inviteCode: String, role: Int, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.role = role
        self.isPrimary = isPrimary
    }

    func withInviteCode(_ inviteCode: String) -> FamilyInfoDTO {
        FamilyInfoDTO(id: id, name: name, inviteCode: inviteCode, role: role, isPrimary: isPrimary)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        role = try container.decodeIfPresent(Int.self, forKey: .role) ?? 0
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }
}

nonisolated struct FamilyInfoResponseDTO: Codable, Sendable {
    let id: Int
    let name: String
    let inviteCode: String
    let families: [FamilyInfoDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        families = try container.decodeIfPresent([FamilyInfoDTO].self, forKey: .families) ?? []
    }
}

nonisolated struct JoinFamilyRequestDTO: Codable, Sendable {
    let inviteCode: String
}

nonisolated struct JoinFamilyResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let auth: AuthResponseDTO?
}

// MARK: - Membership (backend/membership_procs.go)

nonisolated struct FamilyMemberDTO: Codable, Sendable, Identifiable {
    let userId: Int
    let name: String
    let email: String
    let role: Int
    let isOwner: Bool
    let isSelf: Bool

    var id: Int { userId }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(Int.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        role = try container.decodeIfPresent(Int.self, forKey: .role) ?? 0
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        isSelf = try container.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case userId, name, email, role, isOwner, isSelf
    }
}

nonisolated struct FamilyIdRequestDTO: Codable, Sendable {
    let familyId: Int
}

nonisolated struct ListFamilyMembersResponseDTO: Codable, Sendable {
    let familyId: Int
    let members: [FamilyMemberDTO]
    let callerIsOwner: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try container.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        members = try container.decodeIfPresent([FamilyMemberDTO].self, forKey: .members) ?? []
        callerIsOwner = try container.decodeIfPresent(Bool.self, forKey: .callerIsOwner) ?? false
    }
}

nonisolated struct LeaveFamilyResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let auth: AuthResponseDTO?
}

nonisolated struct RemoveFamilyMemberRequestDTO: Codable, Sendable {
    let familyId: Int
    let userId: Int
}

nonisolated struct RemoveFamilyMemberResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let members: [FamilyMemberDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        members = try container.decodeIfPresent([FamilyMemberDTO].self, forKey: .members) ?? []
    }
}

nonisolated struct RotateInviteCodeResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let familyId: Int
    let inviteCode: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        familyId = try container.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
    }
}

nonisolated struct RegisterPushDeviceRequestDTO: Codable, Sendable {
    let token: String
    let platform: String
    let environment: String
    let bundleId: String
}

nonisolated struct RegisterPushDeviceResponseDTO: Codable, Sendable {
    let success: Bool
}

nonisolated struct UnregisterPushDeviceRequestDTO: Codable, Sendable {
    let token: String
}

nonisolated struct UnregisterPushDeviceResponseDTO: Codable, Sendable {
    let success: Bool
}

nonisolated struct PersonDTO: Codable, Sendable {
    let id: Int
    let familyId: Int
    let name: String
    let type: Int
    let gender: Int
    let birthday: Date
    /// The server's own rendering of the age. Not used — `AgeCalculator` computes it locally, because this goes stale the moment a birthday passes.
    let age: String
    /// True while `birthday` is a due date rather than a birth date; it keeps deciding weeks-vs-months after the due date passes.
    let isPregnancy: Bool
    let profilePhotoId: Int?
    let profileCropX: Double?
    let profileCropY: Double?
    let profileCropScale: Double?

    enum CodingKeys: String, CodingKey {
        case id, familyId, name, type, gender, birthday, age, isPregnancy
        case profilePhotoId, profileCropX, profileCropY, profileCropScale
    }

    nonisolated init(
        id: Int,
        familyId: Int,
        name: String,
        type: Int,
        gender: Int,
        birthday: Date,
        age: String,
        isPregnancy: Bool = false,
        profilePhotoId: Int? = nil,
        profileCropX: Double? = nil,
        profileCropY: Double? = nil,
        profileCropScale: Double? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.type = type
        self.gender = gender
        self.birthday = birthday
        self.age = age
        self.isPregnancy = isPregnancy
        self.profilePhotoId = profilePhotoId
        self.profileCropX = profileCropX
        self.profileCropY = profileCropY
        self.profileCropScale = profileCropScale
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        familyId = try container.decode(Int.self, forKey: .familyId)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(Int.self, forKey: .type)
        gender = try container.decode(Int.self, forKey: .gender)
        birthday = try container.decode(Date.self, forKey: .birthday)
        age = try container.decodeIfPresent(String.self, forKey: .age) ?? ""
        // `decodeIfPresent` so a response from a server predating the field reads as "not a pregnancy" rather than failing to decode.
        isPregnancy = try container.decodeIfPresent(Bool.self, forKey: .isPregnancy) ?? false
        profilePhotoId = try container.decodeIfPresent(Int.self, forKey: .profilePhotoId)
        profileCropX = try container.decodeIfPresent(Double.self, forKey: .profileCropX)
        profileCropY = try container.decodeIfPresent(Double.self, forKey: .profileCropY)
        profileCropScale = try container.decodeIfPresent(Double.self, forKey: .profileCropScale)
    }
}

nonisolated struct GrowthDataDTO: Codable, Sendable {
    let id: Int
    let personId: Int
    let familyId: Int
    let measurementType: Int
    let value: Double
    let unit: String
    let measurementDate: Date
    let createdAt: Date
}

nonisolated struct MilestoneDTO: Codable, Sendable {
    let id: Int
    let personId: Int
    let familyId: Int
    let descriptionText: String
    let category: String
    let milestoneDate: Date
    let createdAt: Date
    let photoIds: [Int]
    /// Tags on this milestone. `TagIds` carries `omitempty`, so absent and empty mean the same thing on the way in — unlike `photoIds` on the way out.
    let tagIds: [Int]

    enum CodingKeys: String, CodingKey {
        case id, personId, familyId, category, milestoneDate, createdAt
        case descriptionText = "description"
        case photoIds
        case tagIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        personId = try c.decode(Int.self, forKey: .personId)
        familyId = try c.decode(Int.self, forKey: .familyId)
        descriptionText = try c.decode(String.self, forKey: .descriptionText)
        category = try c.decode(String.self, forKey: .category)
        milestoneDate = try c.decode(Date.self, forKey: .milestoneDate)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        photoIds = try c.decodeIfPresent([Int].self, forKey: .photoIds) ?? []
        tagIds = try c.decodeIfPresent([Int].self, forKey: .tagIds) ?? []
    }
}

nonisolated struct ImageDTO: Codable, Sendable {
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
    let tagIds: [Int]

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
        case tagIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        familyId = try c.decode(Int.self, forKey: .familyId)
        ownerUserId = try c.decode(Int.self, forKey: .ownerUserId)
        originalFilename = try c.decode(String.self, forKey: .originalFilename)
        mimeType = try c.decode(String.self, forKey: .mimeType)
        fileSize = try c.decode(Int.self, forKey: .fileSize)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        filePath = try c.decode(String.self, forKey: .filePath)
        title = try c.decode(String.self, forKey: .title)
        descriptionText = try c.decode(String.self, forKey: .descriptionText)
        photoDate = try c.decode(Date.self, forKey: .photoDate)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        status = try c.decode(Int.self, forKey: .status)
        tagIds = try c.decodeIfPresent([Int].self, forKey: .tagIds) ?? []
    }
}

nonisolated struct TagDTO: Codable, Sendable {
    let id: Int
    let familyId: Int
    let name: String
    let color: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        familyId = try c.decode(Int.self, forKey: .familyId)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, familyId, name, color
    }
}

nonisolated struct ListTagsResponseDTO: Codable, Sendable {
    let tags: [TagDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tags = try container.decodeIfPresent([TagDTO].self, forKey: .tags) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case tags
    }
}

nonisolated struct PhotoWithPeopleDTO: Codable, Sendable {
    let image: ImageDTO
    let people: [PersonDTO]
}

nonisolated struct GetPersonResponseDTO: Codable, Sendable {
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

nonisolated struct ListPeopleResponseDTO: Codable, Sendable {
    let people: [PersonDTO]
}

nonisolated struct AddGrowthDataResponseDTO: Codable, Sendable {
    let growthData: GrowthDataDTO
}

nonisolated struct UpdateGrowthDataResponseDTO: Codable, Sendable {
    let growthData: GrowthDataDTO
}

nonisolated struct AddMilestoneResponseDTO: Codable, Sendable {
    let milestone: MilestoneDTO
}

nonisolated struct UpdateMilestoneResponseDTO: Codable, Sendable {
    let milestone: MilestoneDTO
}

nonisolated struct AddPhotoResponseDTO: Codable, Sendable {
    let image: ImageDTO
}

nonisolated struct UpdatePhotoResponseDTO: Codable, Sendable {
    let image: ImageDTO
}

nonisolated struct GetPhotoResponseDTO: Codable, Sendable {
    let image: ImageDTO
    let people: [PersonDTO]
}

nonisolated struct ListFamilyPhotosResponseDTO: Codable, Sendable {
    let photos: [PhotoWithPeopleDTO]
}

nonisolated struct FamilyTimelineItemDTO: Codable, Sendable {
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

nonisolated struct GetFamilyTimelineResponseDTO: Codable, Sendable {
    let people: [FamilyTimelineItemDTO]
}

// MARK: - Request DTOs

nonisolated struct GoogleTokenLoginRequestDTO: Encodable, Sendable {
    let idToken: String
}

nonisolated struct AddPersonRequestDTO: Encodable, Sendable {
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String  // "yyyy-MM-dd"
}

nonisolated struct UpdatePersonRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String  // "yyyy-MM-dd"
}

nonisolated struct AddGrowthDataRequestDTO: Encodable, Sendable {
    let personId: Int
    let measurementType: String  // "height" or "weight"
    let value: Double
    let unit: String             // "cm", "in", "kg", "lbs"
    let inputType: String        // "date" or "today"
    let measurementDate: String? // "yyyy-MM-dd" if inputType="date"
}

nonisolated struct UpdateGrowthDataRequestDTO: Encodable, Sendable {
    let id: Int
    let measurementType: String
    let value: Double
    let unit: String
    let inputType: String
    let measurementDate: String?
}

nonisolated struct DeleteRequestDTO: Encodable, Sendable {
    let id: Int
}

nonisolated struct SuccessResponseDTO: Decodable, Sendable {
    let success: Bool
}

nonisolated struct AddMilestoneRequestDTO: Encodable, Sendable {
    let personId: Int
    let description: String
    let category: String
    let inputType: String        // "date" or "today"
    let milestoneDate: String?   // "yyyy-MM-dd" if inputType="date"
    /// Photos to attach. `nil` omits the key entirely.
    let photoIds: [Int]?
}

nonisolated struct UpdateMilestoneRequestDTO: Encodable, Sendable {
    let id: Int
    let description: String
    let category: String
    let inputType: String
    let milestoneDate: String?
    /// The complete attachment set, not a delta. `nil` vs `[]` is the distinction that matters: absent leaves attachments alone, empty detaches them all.
    let photoIds: [Int]?
}

nonisolated struct UpdatePhotoRequestDTO: Encodable, Sendable {
    let id: Int
    let title: String
    let description: String
    let inputType: String
    let photoDate: String?
}

nonisolated struct AddPeopleToPhotoRequestDTO: Encodable, Sendable {
    let photoId: Int
    let personIds: [Int]
}

nonisolated struct RemovePersonFromPhotoRequestDTO: Encodable, Sendable {
    let photoId: Int
    let personId: Int
}

/// The complete tag set for a photo, not a delta. Unlike `photoIds` on a milestone there is no absent-vs-empty distinction to preserve.
nonisolated struct UpdatePhotoTagsRequestDTO: Encodable, Sendable {
    let photoId: Int
    let tagIds: [Int]
}

nonisolated struct UpdateMilestoneTagsRequestDTO: Encodable, Sendable {
    let milestoneId: Int
    let tagIds: [Int]
}

/// A proc whose Go response type has no fields at all, which marshals as the literal body `{}`. `SuccessResponseDTO` would throw on the missing key.
nonisolated struct EmptyResponseDTO: Decodable, Sendable {}

nonisolated struct AddPersonResponseDTO: Decodable, Sendable {
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

nonisolated struct UpdatePersonResponseDTO: Decodable, Sendable {
    let person: PersonDTO
}

nonisolated struct SetProfilePhotoRequestDTO: Encodable, Sendable {
    let personId: Int
    let photoId: Int
    let cropX: Double
    let cropY: Double
    let cropScale: Double
}

nonisolated struct SetProfilePhotoResponseDTO: Decodable, Sendable {
    let person: PersonDTO
}

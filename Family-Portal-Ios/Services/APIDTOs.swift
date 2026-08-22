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

/// `CreateAccountRequest` in backend/users.go. An empty `familyCode` starts a
/// new family; a matching invite code joins an existing one. The initial-person
/// fields seed the family with its first member and are skipped entirely when
/// `initialPersonBirthdate` is empty.
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

/// `RequestPasswordResetRequest` in backend/password_reset.go. The response is
/// deliberately identical for known and unknown addresses.
nonisolated struct RequestPasswordResetRequestDTO: Codable, Sendable {
    let email: String
}

nonisolated struct RequestPasswordResetResponseDTO: Codable, Sendable {
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

/// `CheckMobileVersionResponse` in backend/mobile_version.go.
nonisolated struct MobileVersionPolicyDTO: Codable, Sendable {
    let status: String
    let minimumVersion: String
    let latestVersion: String
    let updateUrl: String
    let updateMessage: String
}

/// `FamilyInfo` in backend/users.go — one family the signed-in user belongs to,
/// and what they may do in it.
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

    /// `RotateInviteCode` answers with the new code and nothing else about the
    /// family, so the rest of the row is carried over rather than re-fetched.
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

/// `FamilyInfoResponse`. The top-level fields describe the primary family and
/// predate multi-family membership; `families` is the full list.
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
        // A nil Go slice marshals as null.
        families = try container.decodeIfPresent([FamilyInfoDTO].self, forKey: .families) ?? []
    }
}

/// `JoinFamilyRequest` / `JoinFamilyResponse` in backend/users.go. Joining adds
/// a family rather than moving between them: the primary family is left alone.
nonisolated struct JoinFamilyRequestDTO: Codable, Sendable {
    let inviteCode: String
}

nonisolated struct JoinFamilyResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let auth: AuthResponseDTO?
}

// MARK: - Membership (backend/membership_procs.go)

/// `FamilyMemberView` — one *account* with access to a family, as opposed to a
/// `PersonDTO`, which is somebody the family keeps records about.
///
/// `joinedAt` is deliberately not decoded: it exists to order the list, the
/// server has already applied that order, and a field nothing reads is one more
/// way for the whole list to fail to decode.
nonisolated struct FamilyMemberDTO: Codable, Sendable, Identifiable {
    let userId: Int
    let name: String
    let email: String
    /// `AccessLevel`, the same integer scale as `FamilyInfoDTO.role`.
    let role: Int
    /// The one member who may remove others.
    let isOwner: Bool
    /// The caller, who leaves rather than being removed.
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

/// `ListFamilyMembersRequest` / `FamilyIdRequest`. A zero `familyId` means the
/// caller's primary family, which is the fallback the Go side applies.
nonisolated struct FamilyIdRequestDTO: Codable, Sendable {
    let familyId: Int
}

nonisolated struct ListFamilyMembersResponseDTO: Codable, Sendable {
    let familyId: Int
    let members: [FamilyMemberDTO]
    /// Sent so the UI doesn't have to re-derive who may remove whom.
    let callerIsOwner: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try container.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        // A nil Go slice marshals as null.
        members = try container.decodeIfPresent([FamilyMemberDTO].self, forKey: .members) ?? []
        callerIsOwner = try container.decodeIfPresent(Bool.self, forKey: .callerIsOwner) ?? false
    }
}

/// `LeaveFamilyResponse`. `auth` is a Go *struct*, and `omitempty` has no effect
/// on those, so a refusal still carries a zero-valued one — see
/// `FamilyMembershipService.leaveFamily` for why the id is checked.
nonisolated struct LeaveFamilyResponseDTO: Codable, Sendable {
    let success: Bool
    let error: String?
    let auth: AuthResponseDTO?
}

nonisolated struct RemoveFamilyMemberRequestDTO: Codable, Sendable {
    let familyId: Int
    let userId: Int
}

/// `RemoveFamilyMemberResponse`. The remaining members come back with the
/// success, so a removal needs no follow-up list call.
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

/// `RotateInviteCodeResponse`. `familyId` and `inviteCode` carry `omitempty`, so
/// a refusal omits them entirely rather than sending zero and "".
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

/// `RegisterPushDeviceRequest` in backend/push_notifications.go. The server
/// validates `platform`, `environment`, and `bundleId` against its own APNs
/// configuration and rejects anything that doesn't match.
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
    /// The server's own rendering of the age. Not used — `AgeCalculator`
    /// computes the same string locally, because this one goes stale the moment
    /// a birthday passes and a person created offline has none at all. Decoded
    /// rather than dropped so a test can hold the two side by side.
    let age: String
    /// True while `birthday` is a due date rather than a birth date. It decides
    /// whether the age is weeks or months, and it keeps deciding after the due
    /// date passes — an overdue baby is 41 weeks, not a day old.
    let isPregnancy: Bool
    let profilePhotoId: Int?
    let profileCropX: Double?
    let profileCropY: Double?
    let profileCropScale: Double?

    enum CodingKeys: String, CodingKey {
        case id, familyId, name, type, gender, birthday, age, isPregnancy
        case profilePhotoId, profileCropX, profileCropY, profileCropScale
    }

    /// Written out because the custom decoder below suppresses the synthesized
    /// one, and because `isPregnancy` should not have to be spelled at every
    /// call site that does not care about it.
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
        // `decodeIfPresent` so a response from a server that predates the field
        // reads as "not a pregnancy" rather than failing to decode at all.
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
    /// Tags on this milestone. `TagIds` carries `omitempty` (backend/milestone.go),
    /// so a milestone with no tags omits the key rather than sending `[]` —
    /// absent and empty are the same thing on the way *in*, unlike `photoIds` on
    /// the way out. Every response the app applies populates it
    /// (`AddMilestone`, `UpdateMilestone`, `GetFamilyTimeline`), so taking an
    /// absent key as "no tags" cannot wipe tags the server still holds.
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
    /// Tags on this photo — the same `omitempty` reading as `MilestoneDTO.tagIds`.
    /// `AddPhoto` sets it explicitly to empty for a fresh upload, and `UpdatePhoto`,
    /// `ListFamilyPhotos` and `GetFamilyTimeline` all fill it in, so no response
    /// the app applies leaves the local list guessing.
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

/// `Tag` in backend/tags.go.
///
/// `createdAt` is deliberately not decoded: `ListTags` has already sorted the
/// list by name, nothing in the app shows a tag's age, and a field nothing reads
/// is one more way for the whole list to fail to decode.
nonisolated struct TagDTO: Codable, Sendable {
    let id: Int
    let familyId: Int
    let name: String
    /// A hex string such as `#4A90D9`. `CreateTag` never validates it, so this
    /// can be empty — `TagColor` falls back rather than refusing to draw.
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
        // A nil Go slice marshals as null.
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
    /// The complete attachment set, not a delta: `UpdateMilestoneTx`
    /// (backend/milestone.go) detaches every photo not listed here. The
    /// distinction that matters is `nil` vs `[]` — Go reads an absent key as
    /// "leave the attachments alone" and an empty array as "detach them all",
    /// and `encodeIfPresent` is what keeps those two apart on the wire.
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

/// The complete tag set for a photo, not a delta: `UpdatePhotoTags`
/// (backend/photos.go) detaches every tag not listed and attaches every tag that
/// is. Unlike `photoIds` on a milestone there is no absent-vs-empty distinction
/// to preserve — the proc's only job is this field, and Go normalizes a missing
/// or null `tagIds` to `[]`, so an empty array is the honest way to say "no
/// tags".
nonisolated struct UpdatePhotoTagsRequestDTO: Encodable, Sendable {
    let photoId: Int
    let tagIds: [Int]
}

/// The milestone half of `UpdatePhotoTagsRequestDTO`, against
/// `UpdateMilestoneTags` in backend/milestone.go.
nonisolated struct UpdateMilestoneTagsRequestDTO: Encodable, Sendable {
    let milestoneId: Int
    let tagIds: [Int]
}

/// A proc whose Go response type has no fields at all, which marshals as the
/// literal body `{}`. Decoding `SuccessResponseDTO` against one of those would
/// throw on the missing `success` key and turn every successful write into a
/// retry.
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

/// Crop values are percentages of the image (50/50 is centred) plus a zoom
/// factor. The server substitutes its own defaults for zeros, but sending them
/// explicitly keeps what iOS asked for and what comes back on the next pull the
/// same thing.
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

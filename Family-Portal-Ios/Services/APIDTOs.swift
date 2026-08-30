@preconcurrency import Foundation

nonisolated struct AuthResponseDTO: Sendable {
    let id: Int
    let name: String
    let email: String
    let isAdmin: Bool
    let familyId: Int?
    /// The person record standing in for this account, which is the subject every derived relationship label is phrased against. `omitempty` on the Go side, so an account never linked to a person simply omits the key.
    let personId: Int?

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        isAdmin = try container.decode(Bool.self, forKey: .isAdmin)
        familyId = try container.decodeIfPresent(Int.self, forKey: .familyId)
        personId = try container.decodeIfPresent(Int.self, forKey: .personId)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(email, forKey: .email)
        try container.encode(isAdmin, forKey: .isAdmin)
        try container.encodeIfPresent(familyId, forKey: .familyId)
        try container.encodeIfPresent(personId, forKey: .personId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email, isAdmin, familyId, personId
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
    /// How this person relates to the *caller's* own person, worded by the server ("daughter", "grandfather"). Derived, viewer-relative and `omitempty`: absent whenever the graph does not connect the two.
    let relationship: String?

    enum CodingKeys: String, CodingKey {
        case id, familyId, name, gender, birthday, age, isPregnancy
        case profilePhotoId, profileCropX, profileCropY, profileCropScale
        case relationship
    }

    nonisolated init(
        id: Int,
        familyId: Int,
        name: String,
        gender: Int,
        birthday: Date,
        age: String,
        isPregnancy: Bool = false,
        profilePhotoId: Int? = nil,
        profileCropX: Double? = nil,
        profileCropY: Double? = nil,
        profileCropScale: Double? = nil,
        relationship: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.gender = gender
        self.birthday = birthday
        self.age = age
        self.isPregnancy = isPregnancy
        self.profilePhotoId = profilePhotoId
        self.profileCropX = profileCropX
        self.profileCropY = profileCropY
        self.profileCropScale = profileCropScale
        self.relationship = relationship
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        familyId = try container.decode(Int.self, forKey: .familyId)
        name = try container.decode(String.self, forKey: .name)
        gender = try container.decode(Int.self, forKey: .gender)
        birthday = try container.decode(Date.self, forKey: .birthday)
        age = try container.decodeIfPresent(String.self, forKey: .age) ?? ""
        // `decodeIfPresent` so a response from a server predating the field reads as "not a pregnancy" rather than failing to decode.
        isPregnancy = try container.decodeIfPresent(Bool.self, forKey: .isPregnancy) ?? false
        profilePhotoId = try container.decodeIfPresent(Int.self, forKey: .profilePhotoId)
        profileCropX = try container.decodeIfPresent(Double.self, forKey: .profileCropX)
        profileCropY = try container.decodeIfPresent(Double.self, forKey: .profileCropY)
        profileCropScale = try container.decodeIfPresent(Double.self, forKey: .profileCropScale)
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship)
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
    /// The stored edges among `people`, the same set `ListPeople` returns. The app syncs through this one proc, so without them the roster would have no way to band a family by generation short of a call per person.
    let relations: [RelationDTO]

    nonisolated init(people: [FamilyTimelineItemDTO], relations: [RelationDTO] = []) {
        self.people = people
        self.relations = relations
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        people = try container.decodeIfPresent([FamilyTimelineItemDTO].self, forKey: .people) ?? []
        // A server predating the field, and Go marshalling an empty slice as `null`, both read as "no edges" rather than failing the whole pull.
        relations = try container.decodeIfPresent([RelationDTO].self, forKey: .relations) ?? []
    }
}

// MARK: - Request DTOs

nonisolated struct GoogleTokenLoginRequestDTO: Encodable, Sendable {
    let idToken: String
}

/// `AppleTokenLoginRequest` in backend/apple_auth.go. `name` is only ever non-empty on a user's
/// first authorization; the server treats an empty one as absent and names the account itself.
nonisolated struct AppleTokenLoginRequestDTO: Encodable, Sendable {
    let idToken: String
    let name: String
}

nonisolated struct AddPersonRequestDTO: Encodable, Sendable {
    let name: String
    let gender: Int
    let birthdate: String  // "yyyy-MM-dd"
    /// True while `birthdate` is a due date. The server keeps the age in weeks off this flag rather than off the date, so an overdue baby still reads 41 weeks.
    let isPregnancy: Bool
    /// What the new person is to `anchorId`, as `StatedRelation` codes it. `0` with `anchorId: 0` records no relationship, which the server reads as "not saying yet".
    let stated: Int
    let anchorId: Int
    /// The same stated relation against more people, so "child of Steven and Ruth" is one write. Ids that are 0, the new person, repeated, or already stored are skipped server-side; one naming somebody the caller cannot see fails the whole call.
    let additionalAnchorIds: [Int]

    nonisolated init(
        name: String,
        gender: Int,
        birthdate: String,
        isPregnancy: Bool = false,
        stated: Int,
        anchorId: Int,
        additionalAnchorIds: [Int] = []
    ) {
        self.name = name
        self.gender = gender
        self.birthdate = birthdate
        self.isPregnancy = isPregnancy
        self.stated = stated
        self.anchorId = anchorId
        self.additionalAnchorIds = additionalAnchorIds
    }
}

nonisolated struct UpdatePersonRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let gender: Int
    let birthdate: String  // "yyyy-MM-dd"
    /// Not optional to send: `UpdatePerson` assigns this unconditionally, so omitting it decodes as `false` on the Go side and quietly un-pregnancies the record.
    let isPregnancy: Bool

    nonisolated init(id: Int, name: String, gender: Int, birthdate: String, isPregnancy: Bool = false) {
        self.id = id
        self.name = name
        self.gender = gender
        self.birthdate = birthdate
        self.isPregnancy = isPregnancy
    }
}

// MARK: - Relationships (backend/relation.go)

/// One relationship as the server words it for a subject: `label` is what `personName` is *to the person asked about*, already gendered from the target, so the same edge reads correctly from either end.
/// A row is either **stored** — somebody typed it, and `relationId` names the row to remove — or **implied**, worked out from the edges: the siblings that follow from a shared parent, a grandmother two parent edges up. Implied rows all arrive with `relationId` 0, which is why `id` is composed rather than taken from the wire: keying a list on the wire id would collapse every implied row into one.
nonisolated struct RelationViewDTO: Codable, Sendable, Identifiable {
    let relationId: Int
    let personId: Int
    let personName: String
    let label: String
    /// False when nobody stated this — there is no row behind it, so it cannot be removed.
    let stored: Bool

    var id: String { stored ? "stored-\(relationId)" : "implied-\(personId)" }

    enum CodingKeys: String, CodingKey {
        case relationId = "id"
        case personId, personName, label, stored
    }

    nonisolated init(relationId: Int, personId: Int, personName: String, label: String, stored: Bool = true) {
        self.relationId = relationId
        self.personId = personId
        self.personName = personName
        self.label = label
        self.stored = stored
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relationId = try container.decodeIfPresent(Int.self, forKey: .relationId) ?? 0
        personId = try container.decodeIfPresent(Int.self, forKey: .personId) ?? 0
        personName = try container.decodeIfPresent(String.self, forKey: .personName) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        // A server predating the split sent only stored rows, so its silence means stored.
        stored = try container.decodeIfPresent(Bool.self, forKey: .stored) ?? true
    }
}

/// One stored edge of the graph as it travels — `Relation` in backend/relation.go, carried by `ListPeople` and `GetFamilyTimeline`.
nonisolated struct RelationDTO: Codable, Sendable, Identifiable {
    let id: Int
    let fromId: Int
    let toId: Int
    /// `RelationKind`'s raw value. Decoded as an `Int` rather than the enum so a kind added server-side is dropped rather than failing the whole pull.
    let kind: Int

    nonisolated init(id: Int, fromId: Int, toId: Int, kind: Int) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.kind = kind
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        fromId = try container.decodeIfPresent(Int.self, forKey: .fromId) ?? 0
        toId = try container.decodeIfPresent(Int.self, forKey: .toId) ?? 0
        kind = try container.decodeIfPresent(Int.self, forKey: .kind) ?? 0
    }
}

nonisolated struct GetPersonRelationsRequestDTO: Encodable, Sendable {
    let personId: Int
}

nonisolated struct GetPersonRelationsResponseDTO: Codable, Sendable {
    let personId: Int
    let relations: [RelationViewDTO]
    /// False when the caller may see this person but not edit them, which is the server's own answer rather than something the app re-derives.
    let manageable: Bool

    nonisolated init(personId: Int, relations: [RelationViewDTO], manageable: Bool) {
        self.personId = personId
        self.relations = relations
        self.manageable = manageable
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        personId = try container.decodeIfPresent(Int.self, forKey: .personId) ?? 0
        // Go marshals an empty slice as `null`, and a refusal sends the whole struct zero-valued.
        relations = try container.decodeIfPresent([RelationViewDTO].self, forKey: .relations) ?? []
        manageable = try container.decodeIfPresent(Bool.self, forKey: .manageable) ?? false
    }
}

nonisolated struct AddRelationRequestDTO: Encodable, Sendable {
    let personId: Int
    let anchorId: Int
    /// `StatedRelation`'s raw value: what `personId` is to `anchorId`.
    let stated: Int
    /// More people the same statement applies to, saved in one write. See `AddPersonRequestDTO.additionalAnchorIds` for what the server skips and what it refuses.
    let additionalAnchorIds: [Int]

    nonisolated init(personId: Int, anchorId: Int, stated: Int, additionalAnchorIds: [Int] = []) {
        self.personId = personId
        self.anchorId = anchorId
        self.stated = stated
        self.additionalAnchorIds = additionalAnchorIds
    }
}

nonisolated struct RemoveRelationRequestDTO: Encodable, Sendable {
    let relationId: Int
}

/// `RelationActionResponse`. Refusals arrive as HTTP 200 with `success: false`, and `relations` is a struct, so `omitempty` does nothing for it: a refusal still carries a zero-valued one that must not be mistaken for "this person has no relationships".
nonisolated struct RelationActionResponseDTO: Decodable, Sendable {
    let success: Bool
    let error: String?
    let relations: GetPersonRelationsResponseDTO?
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

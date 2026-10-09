@preconcurrency import Foundation

extension KeyedDecodingContainer {
    /// A list that may be missing: Go marshals a nil slice as `null`, and an absent key reads the same way. For the hand-written decoders that remain; a field that only needs this is `@OrZero`.
    nonisolated func decodeList<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent([T].self, forKey: key) ?? []
    }

    nonisolated func decode<Value: Decodable & ZeroValue>(_ type: OrZero<Value>.Type, forKey key: Key) throws -> OrZero<Value> {
        OrZero(wrappedValue: try decodeIfPresent(Value.self, forKey: key) ?? .zero)
    }
}

/// What Go marshals for an unset field, and so what a missing key means: `omitempty` drops zero values, a nil slice arrives as `null`, and a server older than a field never sends it.
nonisolated protocol ZeroValue {
    static var zero: Self { get }
}

nonisolated extension Int: ZeroValue {}
nonisolated extension Double: ZeroValue {}
nonisolated extension Bool: ZeroValue { static var zero: Bool { false } }
nonisolated extension String: ZeroValue { static var zero: String { "" } }
nonisolated extension Array: ZeroValue { static var zero: Array { [] } }
nonisolated extension Dictionary: ZeroValue { static var zero: Dictionary { [:] } }

/// A field that reads as its zero value when the key is missing or `null`, rather than failing the whole response. The one rule every DTO shares, written once instead of as a hand-written decoder per type; fields left plain still throw when missing, so a malformed response is still caught.
@propertyWrapper
nonisolated struct OrZero<Value: ZeroValue> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

nonisolated extension OrZero: Decodable where Value: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? .zero : try container.decode(Value.self)
    }
}

nonisolated extension OrZero: Encodable where Value: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

nonisolated extension OrZero: Equatable where Value: Equatable {}
nonisolated extension OrZero: Hashable where Value: Hashable {}
nonisolated extension OrZero: Sendable where Value: Sendable {}

nonisolated struct AuthResponseDTO: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
    let isAdmin: Bool
    let familyId: Int?
    /// The person record standing in for this account, which is the subject every derived relationship label is phrased against. `omitempty` on the Go side, so an account never linked to a person simply omits the key.
    let personId: Int?
    /// Every family this account can see and its role in each — what `FamilyAccess` reads to decide which add, edit and delete controls to show.
    @OrZero var families: [FamilyRefDTO]
}

/// One family in the auth response (backend/users.go `FamilyRef`). `role` is the backend's `AccessLevel`; see `FamilyAccess`.
nonisolated struct FamilyRefDTO: Codable, Sendable, Equatable {
    let id: Int
    @OrZero var name: String = ""
    @OrZero var role: Int
    @OrZero var isPrimary: Bool = false
}

/// What every sign-in answers with — password, Google, Apple, a new account — and what `api/refresh` answers with too.
nonisolated struct SessionResponseDTO: Codable, Sendable, Refusable {
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

nonisolated struct RequestPasswordResetRequestDTO: Codable, Sendable {
    let email: String
}

nonisolated struct RequestPasswordResetResponseDTO: Codable, Sendable, Refusable {
    let success: Bool
    let error: String?
}

/// `DeleteAccountRequest` in backend/account_deletion.go. `password` is empty for a Google-only account, where `confirmEmail` carries the whole weight.
nonisolated struct DeleteAccountRequestDTO: Codable, Sendable {
    let password: String
    let confirmEmail: String
}

nonisolated struct DeleteAccountResponseDTO: Codable, Sendable, Refusable {
    let success: Bool
    let error: String?
}

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
    var inviteCode: String
    @OrZero var role: Int
    @OrZero var isPrimary: Bool

    func withInviteCode(_ inviteCode: String) -> FamilyInfoDTO {
        var copy = self
        copy.inviteCode = inviteCode
        return copy
    }
}

nonisolated struct FamilyInfoResponseDTO: Codable, Sendable {
    let id: Int
    let name: String
    let inviteCode: String
    @OrZero var families: [FamilyInfoDTO]
}

nonisolated struct JoinFamilyRequestDTO: Codable, Sendable {
    let inviteCode: String
}

/// Joining or leaving a family: the refreshed identity, since the account's families and primary family may both have changed.
nonisolated struct FamilyChangeResponseDTO: Codable, Sendable, Refusable {
    let success: Bool
    let error: String?
    let auth: AuthResponseDTO?
}

// MARK: - Membership (backend/membership_procs.go)

nonisolated struct FamilyMemberDTO: Codable, Sendable, Identifiable {
    let userId: Int
    let name: String
    let email: String
    @OrZero var role: Int
    @OrZero var isOwner: Bool
    @OrZero var isSelf: Bool

    var id: Int { userId }
}

nonisolated struct FamilyIdRequestDTO: Codable, Sendable {
    let familyId: Int
}

nonisolated struct ListFamilyMembersResponseDTO: Codable, Sendable {
    @OrZero var familyId: Int
    @OrZero var members: [FamilyMemberDTO]
    @OrZero var callerIsOwner: Bool
}

nonisolated struct RemoveFamilyMemberRequestDTO: Codable, Sendable {
    let familyId: Int
    let userId: Int
}

nonisolated struct RemoveFamilyMemberResponseDTO: Codable, Sendable, Refusable {
    let success: Bool
    let error: String?
    @OrZero var members: [FamilyMemberDTO]
}

nonisolated struct RotateInviteCodeResponseDTO: Codable, Sendable, Refusable {
    let success: Bool
    let error: String?
    @OrZero var familyId: Int
    @OrZero var inviteCode: String
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
    @OrZero var age: String
    /// True while `birthday` is a due date rather than a birth date; it keeps deciding weeks-vs-months after the due date passes. Absent from a server predating the field, which reads as "not a pregnancy".
    @OrZero var isPregnancy: Bool = false
    var profilePhotoId: Int? = nil
    var profileCropX: Double? = nil
    var profileCropY: Double? = nil
    var profileCropScale: Double? = nil
    /// How this person relates to the *caller's* own person, worded by the server ("daughter", "grandfather"). Derived, viewer-relative and `omitempty`: absent whenever the graph does not connect the two.
    var relationship: String? = nil
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
    @OrZero var context: String
    let milestoneDate: Date
    let createdAt: Date
    @OrZero var photoIds: [Int]
    /// Tags on this milestone. `TagIds` carries `omitempty`, so absent and empty mean the same thing on the way in — unlike `photoIds` on the way out.
    @OrZero var tagIds: [Int]

    enum CodingKeys: String, CodingKey {
        case id, personId, familyId, category, context, milestoneDate, createdAt
        case descriptionText = "description"
        case photoIds
        case tagIds
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
    @OrZero var tagIds: [Int]

    enum CodingKeys: String, CodingKey {
        case id, familyId, ownerUserId, originalFilename, mimeType, fileSize, width, height, filePath, title
        case descriptionText = "description"
        case photoDate, createdAt, status, tagIds
    }
}

nonisolated struct TagDTO: Codable, Sendable, Identifiable {
    let id: Int
    let familyId: Int
    let name: String
    @OrZero var color: String
    /// What photos this tag should be suggested for, e.g. "kids at the lake cabin". Only the Tags screen shows it; it is not mirrored into `FamilyTag`.
    @OrZero var autoPhrase: String
}

// MARK: - Tag vocabulary (backend/tags.go)
// Online only, like membership changes: a duplicate name is refused by the server, so nothing is queued.

nonisolated struct CreateTagRequestDTO: Encodable, Sendable {
    let name: String
    let color: String
    /// 0 lets the server pick the caller's primary family.
    let familyId: Int
    let autoPhrase: String
}

nonisolated struct UpdateTagRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let color: String
    /// A pointer on the server: absent leaves the phrase alone, empty clears it. The Tags screen always sends what its field holds.
    let autoPhrase: String
}

nonisolated struct DeleteTagRequestDTO: Encodable, Sendable {
    let id: Int
}

/// `CreateTag` and `UpdateTag` both answer with the saved tag.
nonisolated struct TagResponseDTO: Decodable, Sendable {
    let tag: TagDTO
}

nonisolated struct ListTagsResponseDTO: Codable, Sendable {
    @OrZero var tags: [TagDTO]
}

nonisolated struct PhotoWithPeopleDTO: Codable, Sendable {
    let image: ImageDTO
    let people: [PersonDTO]
    /// With `collapseSimilar`, the other photos in this cover's group of similar shots. Absent otherwise.
    var similar: [Int]? = nil
}

nonisolated struct GetPersonResponseDTO: Codable, Sendable {
    let person: PersonDTO?
    @OrZero var growthData: [GrowthDataDTO]
    @OrZero var milestones: [MilestoneDTO]
    @OrZero var photos: [ImageDTO]
}

nonisolated struct ListPeopleResponseDTO: Codable, Sendable {
    let people: [PersonDTO]
}

nonisolated struct AddGrowthDataResponseDTO: Codable, Sendable {
    let growthData: GrowthDataDTO
}

/// Only the values the request sent, height first.
nonisolated struct AddCheckupResponseDTO: Decodable, Sendable {
    @OrZero var growthData: [GrowthDataDTO]
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

nonisolated struct GetPhotoRequestDTO: Encodable, Sendable {
    let id: Int
}

/// One photo with what the analysis knows about it. The app mirrors photos through `ListFamilyPhotos`, so this is fetched only by the photo page, for `place` and `suggestions`.
nonisolated struct GetPhotoResponseDTO: Decodable, Sendable {
    let image: ImageDTO
    @OrZero var people: [PersonDTO]
    /// Only for members of the family that owns the photo, and only when it carries a location.
    let place: PhotoPlaceDTO?
    /// Pending tag suggestions, for people who can tag the photo. Empty wherever the vision daemon isn't running.
    @OrZero var suggestions: [SuggestedTagDTO]
}

/// The sync pull sends this empty and gets every photo in one page. Search fills `query` and pages through `cursor`.
nonisolated struct ListFamilyPhotosRequestDTO: Encodable, Sendable {
    var query: String? = nil
    /// 0 or absent returns every match in one response.
    var limit: Int? = nil
    var cursor: String? = nil
    /// Any-of, like `PhotoFilter`'s people. A name in `query` narrows to all-of on the server's side.
    var personIds: [Int]? = nil
    var tagIds: [Int]? = nil
    var dateFrom: String? = nil  // "yyyy-MM-dd"
    var dateTo: String? = nil
    /// A key from `ListPhotoPlaces`.
    var placeKey: String? = nil
    /// Lists each group of similar shots as its best photo, with the rest in `similar`. Browsing only; a query ignores it.
    var collapseSimilar: Bool? = nil
}

nonisolated struct ListFamilyPhotosResponseDTO: Decodable, Sendable {
    @OrZero var photos: [PhotoWithPeopleDTO]
    /// Empty on the last page. A search's cursors look like `s60`.
    @OrZero var nextCursor: String
    /// For a search: the people named in the query, whom every result shows.
    @OrZero var matchedPersonIds: [Int]
    /// `"semantic"`, or `"text"` when the vision daemon is unavailable and only titles and descriptions were searched. Empty for a plain listing.
    @OrZero var searchMode: String
}

nonisolated struct FamilyTimelineItemDTO: Codable, Sendable {
    let person: PersonDTO
    @OrZero var growthData: [GrowthDataDTO]
    @OrZero var milestones: [MilestoneDTO]
    @OrZero var photos: [ImageDTO]
}

nonisolated struct GetFamilyTimelineResponseDTO: Decodable, Sendable {
    @OrZero var people: [FamilyTimelineItemDTO]
    /// The stored edges among `people`, the same set `ListPeople` returns. The app syncs through this one proc, so without them the roster would have no way to band a family by generation short of a call per person.
    @OrZero var relations: [RelationDTO] = []
    /// Every year with an entry, newest first, whatever the window — History's **Jump to year** menu.
    @OrZero var years: [Int] = []
    /// Empty unless the request set `includeActivities`. Appearances are not in SwiftData; History fetches them per window and caches them beside the activity snapshots.
    @OrZero var appearances: [TimelineAppearanceDTO] = []
}

// MARK: - Request DTOs

nonisolated struct GoogleTokenLoginRequestDTO: Encodable, Sendable {
    let idToken: String
    /// An invite code to join with; empty means none.
    let familyCode: String
}

/// `AppleTokenLoginRequest` in backend/apple_auth.go. `name` is only ever non-empty on a user's
/// first authorization; the server treats an empty one as absent and names the account itself.
nonisolated struct AppleTokenLoginRequestDTO: Encodable, Sendable {
    let idToken: String
    let name: String
    /// Exchanged server-side for the refresh token account deletion revokes, as App Store Review
    /// Guideline 5.1.1(v) requires. The server treats an empty one as "nothing to exchange".
    let authorizationCode: String
    /// An invite code to join with; empty means none.
    let familyCode: String
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
    @OrZero var id: Int
    @OrZero var fromId: Int
    @OrZero var toId: Int
    /// `RelationKind`'s raw value. Decoded as an `Int` rather than the enum so a kind added server-side is dropped rather than failing the whole pull.
    @OrZero var kind: Int
}

nonisolated struct GetPersonRelationsRequestDTO: Encodable, Sendable {
    let personId: Int
}

nonisolated struct GetPersonRelationsResponseDTO: Codable, Sendable {
    /// A refusal sends the whole struct zero-valued, so every field here defaults.
    @OrZero var personId: Int
    @OrZero var relations: [RelationViewDTO]
    /// False when the caller may see this person but not edit them, which is the server's own answer rather than something the app re-derives.
    @OrZero var manageable: Bool
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
nonisolated struct RelationActionResponseDTO: Decodable, Sendable, Refusable {
    let success: Bool
    let error: String?
    let relations: GetPersonRelationsResponseDTO?
}

nonisolated struct AddGrowthDataRequestDTO: Encodable, Sendable {
    let personId: Int
    let measurementType: String  // "height" or "weight"
    let value: Double
    let unit: String             // "cm", "in", "kg", "lbs"
    /// Always "date": the device's local day, never the server's UTC "today".
    let inputType = "date"
    let measurementDate: String? // "yyyy-MM-dd"
}

/// One value of a checkup. The type is the key it is sent under, not a field.
nonisolated struct CheckupValueDTO: Encodable, Sendable {
    let value: Double
    let unit: String
}

/// `AddCheckup`: a height and a weight for one person on one day, in one transaction. Either value may be left out, never both.
nonisolated struct AddCheckupRequestDTO: Encodable, Sendable {
    let personId: Int
    let inputType = "date"
    let measurementDate: String? // "yyyy-MM-dd"
    let height: CheckupValueDTO?
    let weight: CheckupValueDTO?
}

nonisolated struct UpdateGrowthDataRequestDTO: Encodable, Sendable {
    let id: Int
    let measurementType: String
    let value: Double
    let unit: String
    let inputType = "date"
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
    /// Kept only for quotes; the server clears it for any other category.
    let context: String
    /// Always "date": the device's local day, never the server's UTC "today".
    let inputType = "date"
    let milestoneDate: String?   // "yyyy-MM-dd"
    /// Photos to attach. `nil` omits the key entirely.
    let photoIds: [Int]?
    /// Tags to attach in the same transaction, so a milestone never lands without them. `nil` omits the key.
    let tagIds: [Int]?
}

nonisolated struct UpdateMilestoneRequestDTO: Encodable, Sendable {
    let id: Int
    let description: String
    let category: String
    /// Sent every time: an update without it clears the context.
    let context: String
    let inputType = "date"
    let milestoneDate: String?
    /// The complete attachment set, not a delta. `nil` vs `[]` is the distinction that matters: absent leaves attachments alone, empty detaches them all.
    let photoIds: [Int]?
    /// The complete tag set, with the same `nil`-vs-`[]` rule as `photoIds`. An editor that did not show the tag picker sends `nil`.
    let tagIds: [Int]?
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
    @OrZero var growthData: [GrowthDataDTO]
    @OrZero var milestones: [MilestoneDTO]
    @OrZero var photos: [ImageDTO]
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

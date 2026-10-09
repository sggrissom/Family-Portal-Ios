import Foundation

// MARK: - Gender Mapping

func genderToInt(_ gender: Gender) -> Int {
    switch gender {
    case .male: return 0
    case .female: return 1
    case .other: return 2
    }
}

func intToGender(_ value: Int) -> Gender {
    switch value {
    case 0: return .male
    case 1: return .female
    case 2: return .other
    default: return .other
    }
}

// MARK: - MeasurementType Mapping

func measurementTypeToString(_ type: MeasurementType) -> String {
    switch type {
    case .height: return "height"
    case .weight: return "weight"
    }
}

func intToMeasurementType(_ value: Int) -> MeasurementType {
    switch value {
    case 0: return .height
    case 1: return .weight
    default: return .height
    }
}

// MARK: - MeasurementUnit Mapping

func unitToString(_ unit: MeasurementUnit) -> String {
    switch unit {
    case .centimeters: return "cm"
    case .inches: return "in"
    case .kilograms: return "kg"
    case .pounds: return "lbs"
    }
}

func unitFromString(_ value: String) -> MeasurementUnit {
    switch value {
    case "cm": return .centimeters
    case "in": return .inches
    case "kg": return .kilograms
    case "lbs": return .pounds
    default: return .inches
    }
}

// MARK: - Date Formatting

/// The calendar day a write sends, as `YYYY-MM-DD`, from a record date (see `Date.recordDay`).
func dateToAPIString(_ date: Date) -> String {
    date.recordDayKey
}

// MARK: - Model Apply Functions

func applyPersonDTO(_ dto: PersonDTO, to person: Person) {
    person.remoteId = String(dto.id)
    person.familyRemoteId = dto.familyId == 0 ? nil : dto.familyId
    person.name = dto.name
    person.gender = intToGender(dto.gender)
    person.relationship = nonEmpty(dto.relationship)
    person.birthday = dto.birthday.recordDate
    person.isPregnancy = dto.isPregnancy
    person.profilePhotoId = nonZero(dto.profilePhotoId)
    person.profileCropX = nonZero(dto.profileCropX)
    person.profileCropY = nonZero(dto.profileCropY)
    person.profileCropScale = nonZero(dto.profileCropScale)
}

/// Applies an edge whose kind this build understands. An unknown kind returns `false` and the caller drops the edge: guessing would be worse than ignoring it, since only `.parent` implies a generation step and picking wrong moves people between bands.
func applyRelationDTO(_ dto: RelationDTO, to relation: PersonRelation) -> Bool {
    guard let kind = RelationKind(rawValue: dto.kind) else { return false }
    relation.remoteId = String(dto.id)
    relation.fromId = dto.fromId
    relation.toId = dto.toId
    relation.kind = kind
    return true
}

/// The backend marshals these as plain Go numbers, so "unset" arrives as `0` rather than as an absent key — taken literally, every avatar asked to load photo id 0.
private func nonZero(_ value: Int?) -> Int? {
    guard let value, value != 0 else { return nil }
    return value
}

private func nonZero(_ value: Double?) -> Double? {
    guard let value, value != 0 else { return nil }
    return value
}

/// A relationship the graph could not name comes back as an omitted key from most procs but as `""` from the ones that build it field by field; both mean "unrelated as far as the server can tell".
private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

func applyGrowthDataDTO(_ dto: GrowthDataDTO, to growthData: GrowthData) {
    growthData.remoteId = String(dto.id)
    growthData.measurementType = intToMeasurementType(dto.measurementType)
    growthData.value = dto.value
    growthData.unit = unitFromString(dto.unit)
    growthData.date = dto.measurementDate.recordDate
}

/// Maps an `AddCheckup` answer back onto the records that asked for it, by measurement type rather than position: the response holds only the values sent.
func applyCheckupResponse(_ response: AddCheckupResponseDTO, height: GrowthData?, weight: GrowthData?) {
    for dto in response.growthData {
        let record = intToMeasurementType(dto.measurementType) == .height ? height : weight
        if let record {
            applyGrowthDataDTO(dto, to: record)
        }
    }
}

func applyMilestoneDTO(_ dto: MilestoneDTO, to milestone: Milestone) {
    milestone.remoteId = String(dto.id)
    milestone.descriptionText = dto.descriptionText
    milestone.category = MilestoneCategory(rawValue: dto.category) ?? .other
    milestone.context = dto.context
    milestone.date = dto.milestoneDate.recordDate
    milestone.photoRemoteIds = dto.photoIds
    milestone.tagRemoteIds = dto.tagIds
}

func applyPhotoDTO(_ dto: ImageDTO, to photo: Photo) {
    photo.remoteId = String(dto.id)
    photo.familyRemoteId = dto.familyId == 0 ? nil : dto.familyId
    photo.title = dto.title
    photo.descriptionText = dto.descriptionText
    photo.photoDate = dto.photoDate
    photo.tagRemoteIds = dto.tagIds
}

func applyTagDTO(_ dto: TagDTO, to tag: FamilyTag) {
    tag.remoteId = String(dto.id)
    tag.name = dto.name
    tag.colorHex = dto.color
    tag.familyId = dto.familyId
}

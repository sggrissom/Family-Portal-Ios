import Foundation

// MARK: - PersonType Mapping

func personTypeToInt(_ type: PersonType) -> Int {
    switch type {
    case .parent: return 0
    case .child: return 1
    }
}

func intToPersonType(_ value: Int) -> PersonType {
    switch value {
    case 0: return .parent
    case 1: return .child
    default: return .child
    }
}

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

private let apiDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

func dateToAPIString(_ date: Date) -> String {
    apiDateFormatter.string(from: date)
}

// MARK: - Model Apply Functions

func applyPersonDTO(_ dto: PersonDTO, to person: Person) {
    person.remoteId = String(dto.id)
    person.name = dto.name
    person.type = intToPersonType(dto.type)
    person.gender = intToGender(dto.gender)
    person.birthday = dto.birthday
}

func applyGrowthDataDTO(_ dto: GrowthDataDTO, to growthData: GrowthData) {
    growthData.remoteId = String(dto.id)
    growthData.measurementType = intToMeasurementType(dto.measurementType)
    growthData.value = dto.value
    growthData.unit = unitFromString(dto.unit)
    growthData.date = dto.measurementDate
}

func applyMilestoneDTO(_ dto: MilestoneDTO, to milestone: Milestone) {
    milestone.remoteId = String(dto.id)
    milestone.descriptionText = dto.descriptionText
    milestone.category = MilestoneCategory(rawValue: dto.category) ?? .other
    milestone.date = dto.milestoneDate
}

func applyPhotoDTO(_ dto: ImageDTO, to photo: Photo) {
    photo.remoteId = String(dto.id)
    photo.title = dto.title
    photo.descriptionText = dto.descriptionText
    photo.photoDate = dto.photoDate
}

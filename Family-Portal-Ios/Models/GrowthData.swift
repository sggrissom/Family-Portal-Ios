import Foundation
import SwiftData

@Model
final class GrowthData {
    var id: UUID
    var remoteId: String?
    var measurementType: MeasurementType
    var value: Double
    var unit: MeasurementUnit
    var date: Date

    var person: Person?

    init(measurementType: MeasurementType, value: Double, unit: MeasurementUnit, date: Date) {
        self.id = UUID()
        self.remoteId = nil
        self.measurementType = measurementType
        self.value = value
        self.unit = unit
        self.date = date
        self.person = nil
    }
}

import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID
    var remoteId: String?
    var name: String
    var type: PersonType
    var gender: Gender
    var birthday: Date?
    var profilePhotoId: UUID?

    var family: Family?

    @Relationship(deleteRule: .cascade, inverse: \GrowthData.person)
    var growthData: [GrowthData]

    @Relationship(deleteRule: .cascade, inverse: \Milestone.person)
    var milestones: [Milestone]

    var photos: [Photo]

    init(name: String, type: PersonType, gender: Gender, birthday: Date? = nil) {
        self.id = UUID()
        self.remoteId = nil
        self.name = name
        self.type = type
        self.gender = gender
        self.birthday = birthday
        self.profilePhotoId = nil
        self.family = nil
        self.growthData = []
        self.milestones = []
        self.photos = []
    }
}

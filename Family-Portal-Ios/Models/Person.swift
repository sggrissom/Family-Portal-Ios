import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID = UUID()
    var remoteId: String? = nil
    var name: String
    var type: PersonType
    var gender: Gender
    var birthday: Date? = nil
    var profilePhotoId: Int? = nil

    var family: Family? = nil

    @Relationship(deleteRule: .cascade)
    var growthData: [GrowthData] = []

    @Relationship(deleteRule: .cascade)
    var milestones: [Milestone] = []

    @Relationship(deleteRule: .nullify)
    var photos: [Photo] = []
    
    init(
        id: UUID = UUID(),
        remoteId: String? = nil,
        name: String,
        type: PersonType,
        gender: Gender,
        birthday: Date? = nil,
        profilePhotoId: Int? = nil,
        family: Family? = nil,
        growthData: [GrowthData] = [],
        milestones: [Milestone] = [],
        photos: [Photo] = []
    ) {
        self.id = id
        self.remoteId = remoteId
        self.name = name
        self.type = type
        self.gender = gender
        self.birthday = birthday
        self.profilePhotoId = profilePhotoId
        self.family = family
        self.growthData = growthData
        self.milestones = milestones
        self.photos = photos
    }
}

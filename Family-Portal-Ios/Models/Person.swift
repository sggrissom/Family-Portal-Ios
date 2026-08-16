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

    /// How the profile photo is framed inside the avatar circle: an origin in
    /// percent plus a zoom factor, matching the backend's `profileCrop*` fields.
    /// Only the web can edit these; iOS stores them so a crop chosen there is
    /// rendered the same way here. `nil` means centred at 1× — the server sends
    /// Go zero values for a photo whose crop was never set.
    var profileCropX: Double? = nil
    var profileCropY: Double? = nil
    var profileCropScale: Double? = nil

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

import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID = UUID()
    var remoteId: String? = nil
    var name: String
    var gender: Gender
    var birthday: Date? = nil
    /// True while `birthday` is a due date rather than a birth date, which is what makes the age read in weeks.
    var isPregnancy: Bool = false
    var profilePhotoId: Int? = nil

    /// The server's wording for how this person relates to the signed-in account's own person — "daughter", "grandfather", "cousin" — derived by walking the relation graph in backend/relation_label.go. Read-only here and `nil` for anyone the graph doesn't reach, including when the account has no person of its own to phrase it against.
    var relationship: String? = nil

    /// How the profile photo is framed inside the avatar circle. Editable only on the web; `nil` means centred at 1×, and the server sends Go zero values for a crop that was never set.
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
        gender: Gender,
        birthday: Date? = nil,
        isPregnancy: Bool = false,
        profilePhotoId: Int? = nil,
        relationship: String? = nil,
        family: Family? = nil,
        growthData: [GrowthData] = [],
        milestones: [Milestone] = [],
        photos: [Photo] = []
    ) {
        self.id = id
        self.remoteId = remoteId
        self.name = name
        self.gender = gender
        self.birthday = birthday
        self.isPregnancy = isPregnancy
        self.profilePhotoId = profilePhotoId
        self.relationship = relationship
        self.family = family
        self.growthData = growthData
        self.milestones = milestones
        self.photos = photos
    }
}

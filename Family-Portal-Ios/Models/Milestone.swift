import Foundation
import SwiftData

@Model
final class Milestone {
    var id: UUID
    var remoteId: String?
    var descriptionText: String
    var category: MilestoneCategory
    var date: Date
    var photoRemoteIds: [Int] = []
    /// Ids of the `FamilyTag`s on this milestone; see `Photo.tagRemoteIds`.
    var tagRemoteIds: [Int] = []

    var person: Person?

    init(descriptionText: String, category: MilestoneCategory, date: Date) {
        self.id = UUID()
        self.remoteId = nil
        self.descriptionText = descriptionText
        self.category = category
        self.date = date
        self.person = nil
    }
}

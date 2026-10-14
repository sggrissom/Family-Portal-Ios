import Foundation
import SwiftData

@Model
final class Milestone {
    var id: UUID
    var remoteId: String?
    var descriptionText: String
    var category: MilestoneCategory
    /// Where or why a quote was said. Empty for every other category.
    var context: String = ""
    var date: Date
    var photoRemoteIds: [Int] = []
    /// Ids of the `FamilyTag`s on this milestone; see `Photo.tagRemoteIds`.
    var tagRemoteIds: [Int] = []
    /// For an interview answer, the server ids of its interview and question; 0 for every other moment. `context` then holds the question as it was asked.
    var interviewId: Int = 0
    var questionId: Int = 0

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

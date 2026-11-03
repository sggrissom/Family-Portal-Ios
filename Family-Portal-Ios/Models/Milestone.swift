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
    /// False when the date is approximate, an age, or unknown: `date` is then only where it sorts, and `recordTime` says what to show. Stored on its own so lists can filter without decoding.
    var hasExactDate: Bool = true
    /// The encoded `RecordTime`, `nil` for a record from an older server or one made on this device.
    var recordTimeData: Data? = nil

    var person: Person?

    init(descriptionText: String, category: MilestoneCategory, date: Date) {
        self.id = UUID()
        self.remoteId = nil
        self.descriptionText = descriptionText
        self.category = category
        self.date = date
        self.person = nil
    }

    /// The date as the family gave it: the day when it is exact, otherwise "At age 4", "Around 1970".
    func dateText(_ style: Date.FormatStyle.DateStyle) -> String {
        hasExactDate ? date.displayDay().formatted(date: style, time: .omitted) : (recordTime?.label ?? "")
    }

    var recordTime: RecordTime? {
        get { recordTimeData.flatMap { try? JSONDecoder().decode(RecordTime.self, from: $0) } }
        set {
            recordTimeData = newValue.flatMap { try? JSONEncoder().encode($0) }
            hasExactDate = newValue?.isExactDay ?? true
        }
    }
}

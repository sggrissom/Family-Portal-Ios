import Foundation
import SwiftData

@Model
final class Photo {
    var id: UUID
    var remoteId: String?

    @Attribute(.externalStorage)
    var imageData: Data?

    var title: String
    var descriptionText: String
    var photoDate: Date

    @Relationship(inverse: \Person.photos)
    var taggedPeople: [Person]

    init(title: String, descriptionText: String, photoDate: Date, imageData: Data? = nil) {
        self.id = UUID()
        self.remoteId = nil
        self.imageData = imageData
        self.title = title
        self.descriptionText = descriptionText
        self.photoDate = photoDate
        self.taggedPeople = []
    }
}

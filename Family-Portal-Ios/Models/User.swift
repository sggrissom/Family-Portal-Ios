import Foundation
import SwiftData

@Model
final class User {
    var id: UUID
    var remoteId: String?
    var name: String
    var email: String
    var familyId: UUID?

    init(name: String, email: String, familyId: UUID? = nil) {
        self.id = UUID()
        self.remoteId = nil
        self.name = name
        self.email = email
        self.familyId = familyId
    }
}

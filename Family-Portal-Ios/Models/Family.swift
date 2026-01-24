import Foundation
import SwiftData

@Model
final class Family {
    var id: UUID
    var remoteId: String?
    var name: String
    var inviteCode: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Person.family)
    var members: [Person]

    init(name: String, inviteCode: String) {
        self.id = UUID()
        self.remoteId = nil
        self.name = name
        self.inviteCode = inviteCode
        self.createdAt = Date()
        self.members = []
    }
}

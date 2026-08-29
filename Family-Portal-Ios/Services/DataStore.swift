import Foundation
import SwiftData

struct DataStore {
    static let shared = DataStore()

    /// Every `@Model` the app stores, in one place, so previews and tests cannot drift from the app's schema.
    /// A function rather than a stored constant so it can be `nonisolated`: the test target builds its containers off the main actor.
    nonisolated static func makeSchema() -> Schema {
        Schema([
            Family.self,
            Person.self,
            GrowthData.self,
            Milestone.self,
            Photo.self,
            User.self,
            ChatMessage.self,
            FamilyTag.self
        ])
    }

    let container: ModelContainer

    private init() {
        let schema = Self.makeSchema()
        let configuration = ModelConfiguration(schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

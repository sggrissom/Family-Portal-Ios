import Foundation
import SwiftData

struct DataStore {
    static let shared = DataStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            Family.self,
            Person.self,
            GrowthData.self,
            Milestone.self,
            Photo.self,
            User.self,
            ChatMessage.self
        ])
        let configuration = ModelConfiguration(schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

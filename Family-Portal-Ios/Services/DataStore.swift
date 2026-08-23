import Foundation
import SwiftData

struct DataStore {
    static let shared = DataStore()

    /// Every `@Model` the app stores, in one place.
    ///
    /// Previews and tests build their own in-memory containers and used to
    /// write this list out again, which is how `PreviewData` came to be missing
    /// `ChatMessage`: any preview that touched a chat model crashed, and the
    /// build said nothing, because a schema is data rather than a type. A model
    /// added later now reaches all three by construction.
    ///
    /// A function rather than a stored constant so it can be `nonisolated`:
    /// the test target builds its containers off the main actor, and a shared
    /// `Schema` instance would have to be `Sendable` to reach it. Building one
    /// is cheap and happens three times in a process.
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

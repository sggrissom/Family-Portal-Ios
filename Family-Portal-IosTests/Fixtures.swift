import Foundation
import SwiftData
@testable import Family_Portal_Ios

/// JSON bodies shaped like `json.Marshal` output for the Go types in
/// `../Family-Portal/backend`. Built as dictionaries rather than string literals
/// so a test can vary one field without restating the whole payload.
nonisolated enum Fixture {

    // MARK: - Sync

    static func person(
        id: Int,
        name: String = "Rowan",
        type: Int = 1,
        gender: Int = 0,
        birthday: String = "2019-08-04T00:00:00Z",
        familyId: Int = 7,
        profilePhotoId: Int? = nil,
        profileCropX: Double? = nil,
        profileCropY: Double? = nil,
        profileCropScale: Double? = nil
    ) -> [String: Any] {
        var person: [String: Any] = [
            "id": id,
            "familyId": familyId,
            "name": name,
            "type": type,
            "gender": gender,
            "birthday": birthday,
            "age": "6 years"
        ]
        if let profilePhotoId {
            person["profilePhotoId"] = profilePhotoId
        }
        if let profileCropX {
            person["profileCropX"] = profileCropX
        }
        if let profileCropY {
            person["profileCropY"] = profileCropY
        }
        if let profileCropScale {
            person["profileCropScale"] = profileCropScale
        }
        return person
    }

    /// A person as the backend actually marshals one with no profile photo set:
    /// Go writes zero values, not absent keys.
    static func personWithUnsetProfilePhoto(id: Int, name: String = "Rowan") -> [String: Any] {
        var person = self.person(id: id, name: name)
        person["profilePhotoId"] = 0
        person["profileCropX"] = 0
        person["profileCropY"] = 0
        person["profileCropScale"] = 0
        return person
    }

    static func growthData(
        id: Int,
        personId: Int,
        measurementType: Int = 0,
        value: Double = 104.5,
        unit: String = "cm",
        measurementDate: String = "2026-01-05T00:00:00Z",
        familyId: Int = 7
    ) -> [String: Any] {
        [
            "id": id,
            "personId": personId,
            "familyId": familyId,
            "measurementType": measurementType,
            "value": value,
            "unit": unit,
            "measurementDate": measurementDate,
            "createdAt": measurementDate
        ]
    }

    /// `tagIds` defaults to absent rather than `[]` because that is what Go
    /// marshals for a milestone with no tags — the field carries `omitempty`.
    static func milestone(
        id: Int,
        personId: Int,
        description: String = "First steps",
        category: String = "development",
        milestoneDate: String = "2026-01-05T00:00:00Z",
        familyId: Int = 7,
        photoIds: [Int] = [],
        tagIds: [Int]? = nil
    ) -> [String: Any] {
        var milestone: [String: Any] = [
            "id": id,
            "personId": personId,
            "familyId": familyId,
            "description": description,
            "category": category,
            "milestoneDate": milestoneDate,
            "createdAt": milestoneDate,
            "photoIds": photoIds
        ]
        if let tagIds {
            milestone["tagIds"] = tagIds
        }
        return milestone
    }

    static func image(
        id: Int,
        title: String = "Beach",
        description: String = "",
        photoDate: String = "2026-01-05T00:00:00Z",
        familyId: Int = 7,
        tagIds: [Int]? = nil
    ) -> [String: Any] {
        var image: [String: Any] = [
            "id": id,
            "familyId": familyId,
            "ownerUserId": 1,
            "originalFilename": "photo.jpg",
            "mimeType": "image/jpeg",
            "fileSize": 1024,
            "width": 800,
            "height": 600,
            "filePath": "photos/\(id).jpg",
            "title": title,
            "description": description,
            "photoDate": photoDate,
            "createdAt": photoDate,
            "status": 0
        ]
        if let tagIds {
            image["tagIds"] = tagIds
        }
        return image
    }

    // MARK: - Tags

    static func tag(
        id: Int,
        name: String = "Holiday",
        color: String = "#4A90D9",
        familyId: Int = 7
    ) -> [String: Any] {
        [
            "id": id,
            "familyId": familyId,
            "name": name,
            "color": color,
            "createdAt": "2025-11-02T09:00:00Z"
        ]
    }

    static func tags(_ tags: [[String: Any]]) -> [String: Any] {
        ["tags": tags]
    }

    static func timelineItem(
        person: [String: Any],
        growthData: [[String: Any]] = [],
        milestones: [[String: Any]] = [],
        photos: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "person": person,
            "growthData": growthData,
            "milestones": milestones,
            "photos": photos
        ]
    }

    static func timeline(_ items: [[String: Any]]) -> [String: Any] {
        ["people": items]
    }

    static func familyPhotos(_ photos: [(image: [String: Any], people: [[String: Any]])]) -> [String: Any] {
        ["photos": photos.map { ["image": $0.image, "people": $0.people] }]
    }

    // MARK: - Chat

    static func chatMessage(
        id: Int,
        userId: Int = 1,
        userName: String = "Ada",
        content: String = "hello",
        createdAt: String = "2026-01-05T12:00:00Z",
        clientMessageId: String = "",
        familyId: Int = 7
    ) -> [String: Any] {
        [
            "id": id,
            "familyId": familyId,
            "userId": userId,
            "userName": userName,
            "content": content,
            "createdAt": createdAt,
            "clientMessageId": clientMessageId
        ]
    }

    /// The same fixture as it arrives over the WebSocket, decoded through the
    /// app's own decoder so the date handling matches the live path.
    static func chatMessageDTO(
        id: Int,
        userId: Int = 1,
        userName: String = "Ada",
        content: String = "hello",
        createdAt: String = "2026-01-05T12:00:00Z",
        clientMessageId: String = ""
    ) throws -> ChatMessageDTO {
        let json = chatMessage(
            id: id,
            userId: userId,
            userName: userName,
            content: content,
            createdAt: createdAt,
            clientMessageId: clientMessageId
        )
        return try APIClient.decode(ChatMessageDTO.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// A private store per test: SwiftData in memory, and a `SyncQueue` on a scratch
/// `UserDefaults` suite so nothing reaches the queue the app itself uses.
nonisolated enum TestStore {

    static func makeContext() throws -> ModelContext {
        let schema = Schema([
            Family.self,
            Person.self,
            GrowthData.self,
            Milestone.self,
            Photo.self,
            User.self,
            ChatMessage.self,
            FamilyTag.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    static func makeQueue() -> SyncQueue {
        let name = "FamilyPortalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SyncQueue(defaults: defaults)
    }
}

/// A `SyncService` wired to a fake backend, its own store and its own queue.
@MainActor
enum TestSync {

    struct Harness {
        let server: FakeHTTPServer
        let service: SyncService
        let context: ModelContext
        /// Held so the monitor stays fixed where the test put it.
        let monitor: NetworkMonitor
    }

    static func harness(connected: Bool = true) throws -> Harness {
        let server = FakeHTTPServer()
        let context = try TestStore.makeContext()
        let monitor = NetworkMonitor(startMonitoring: false)
        monitor.isConnected = connected

        let service = SyncService(
            modelContext: context,
            apiClient: server.apiClient(),
            networkMonitor: monitor,
            syncQueue: TestStore.makeQueue()
        )
        return Harness(server: server, service: service, context: context, monitor: monitor)
    }
}

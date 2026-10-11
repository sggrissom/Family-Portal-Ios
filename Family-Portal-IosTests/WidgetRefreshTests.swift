import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Widget background refresh")
struct WidgetRefreshTests {

    private static func publisher() -> WidgetPublisher {
        let name = "WidgetRefreshTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = WidgetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true))
        return WidgetPublisher(makeStore: { store }, images: nil, defaults: defaults, reloadTimelines: {})
    }

    @Test("The widgets are live for whoever was last published, until they are cleared")
    func liveOwner() async throws {
        let publisher = Self.publisher()
        var published = 0
        publisher.onPublished = { published += 1 }
        #expect(publisher.liveOwner == nil)

        await publisher.publish(context: try TestStore.makeContext(), ownerUserId: 12)
        #expect(publisher.liveOwner == 12)
        #expect(published == 1)

        publisher.clear()
        #expect(publisher.liveOwner == nil)
    }

    @Test("The next refresh is booked a few minutes into the next local day")
    func nextRun() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 22))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 0, minute: 10))!
        #expect(WidgetBackgroundRefresh.nextRun(after: evening, calendar: calendar) == expected)
    }
}

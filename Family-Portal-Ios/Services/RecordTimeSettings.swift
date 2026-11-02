import Foundation
import Observation
import os

nonisolated struct RecordTimeSettingsDTO: Decodable, Sendable {
    @OrZero var approximateDates: Bool
    @OrZero var version: Int
}

/// Whether the server takes approximate dates. Until it says so the app offers only the day-based "When" control, which is all an older server accepts. Remembered across launches so the forms don't change shape offline.
@MainActor
@Observable
final class RecordTimeSettings {
    static let shared = RecordTimeSettings()

    private static let key = "recordTime.approximateDates"

    private(set) var approximateDates = UserDefaults.standard.bool(forKey: RecordTimeSettings.key)

    /// Asks the server; on any failure keeps what it knew.
    func refresh(apiClient: APIClient = .shared) async {
        do {
            let settings: RecordTimeSettingsDTO = try await apiClient.callRPC(.getRecordTimeSettings, payload: EmptyRequestDTO())
            approximateDates = settings.approximateDates
            UserDefaults.standard.set(settings.approximateDates, forKey: Self.key)
        } catch {
            AppLog.ui.error("Record time settings failed: \(String(describing: error), privacy: .public)")
        }
    }
}

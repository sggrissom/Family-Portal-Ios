import Foundation
import OSLog

/// `GetSameAge` responses, kept for the session only, keyed by (anchor, age) — both as asked and as the server answered, so opening "now" and then stepping back to the same age reuses one answer.
/// Same age is read many times in a session (every record detail shows a strip) and never written, and a stale answer from yesterday is worse than none; so nothing goes to disk.
@MainActor
final class SameAgeCache {
    static let shared = SameAgeCache()

    private var responses: [String: GetSameAgeResponseDTO] = [:]

    static func key(ageMonths: Int?, fromPersonId: Int) -> String {
        "\(fromPersonId)-\(ageMonths.map(String.init) ?? "now")"
    }

    func response(ageMonths: Int?, fromPersonId: Int) -> GetSameAgeResponseDTO? {
        responses[Self.key(ageMonths: ageMonths, fromPersonId: fromPersonId)]
    }

    func store(_ response: GetSameAgeResponseDTO, askedAge: Int?, askedFrom: Int) {
        responses[Self.key(ageMonths: askedAge, fromPersonId: askedFrom)] = response
        responses[Self.key(ageMonths: response.ageMonths, fromPersonId: response.fromPersonId)] = response
    }

    func removeAll() {
        responses = [:]
    }
}

/// Loads one Same age answer for a view. Offline with nothing cached, it says so rather than showing empty rows.
@MainActor
@Observable
final class SameAgeLoader {
    enum State {
        case idle
        case loading
        case loaded(GetSameAgeResponseDTO)
        case offline
        case failed(String)
    }

    private(set) var state: State = .idle

    var response: GetSameAgeResponseDTO? {
        if case .loaded(let response) = state { return response }
        return nil
    }

    private let apiClient: APIClient
    private let cache: SameAgeCache

    init(apiClient: APIClient = .shared, cache: SameAgeCache? = nil) {
        self.apiClient = apiClient
        self.cache = cache ?? .shared
    }

    /// `ageMonths` nil asks for the anchor's current age — or, with no anchor (0), the youngest own child's.
    func load(ageMonths: Int?, fromPersonId: Int, isConnected: Bool) async {
        if let cached = cache.response(ageMonths: ageMonths, fromPersonId: fromPersonId) {
            state = .loaded(cached)
            return
        }
        guard isConnected else {
            state = .offline
            return
        }
        state = .loading
        do {
            let response: GetSameAgeResponseDTO = try await apiClient.callRPC(
                .getSameAge,
                payload: GetSameAgeRequestDTO(
                    ageMonths: ageMonths,
                    fromPersonId: fromPersonId,
                    today: WhenEntry.localDateString(Date())
                )
            )
            cache.store(response, askedAge: ageMonths, askedFrom: fromPersonId)
            state = .loaded(response)
        } catch {
            AppLog.ui.error("Same age failed: \(String(describing: error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

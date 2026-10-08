import Foundation
import OSLog

/// How a Same age answer is fetched — the live proc, or a test's stand-in.
typealias SameAgeFetch = @MainActor (GetSameAgeRequestDTO) async throws -> GetSameAgeResponseDTO

extension APIClient {
    /// `GetSameAge` as a `SameAgeFetch`.
    nonisolated func sameAgeFetch() -> SameAgeFetch {
        { request in try await self.callRPC(.getSameAge, payload: request) }
    }
}

/// `GetSameAge` responses, kept for the session only, keyed by what was asked — and again by the age and anchor the server answered with, so opening "now" and then stepping back to the same age reuses one answer.
/// Same age is read many times in a session (every record detail shows a strip) and never written, and a stale answer from yesterday is worse than none; so nothing goes to disk.
@MainActor
final class SameAgeCache {
    static let shared = SameAgeCache()

    private var responses: [String: GetSameAgeResponseDTO] = [:]

    /// The day is in every key: who has reached an age, which row says "now", and where a direct visit starts all move at midnight.
    /// A discovering answer is keyed apart, so a strip's lightweight answer can never stand in for the browse page's first load, which needs the age lists. `details` only changes the age the server picks when it was given neither an age nor a person, so it counts only then.
    static func key(_ request: GetSameAgeRequestDTO) -> String {
        var key = "\(request.today)|\(request.fromPersonId)|\(request.ageMonths.map(String.init) ?? "now")"
        if request.includeAvailableAges {
            key += "|ages"
            if request.details && request.ageMonths == nil && request.fromPersonId == 0 { key += "|details" }
        }
        return key
    }

    func response(for request: GetSameAgeRequestDTO) -> GetSameAgeResponseDTO? {
        responses[Self.key(request)]
    }

    func store(_ response: GetSameAgeResponseDTO, for request: GetSameAgeRequestDTO) {
        responses[Self.key(request)] = response
        // The rows for an age and anchor are the same however they were asked for, so a discovering answer also serves a later lightweight ask for the age it settled on — never the other way round.
        var answered = GetSameAgeRequestDTO(ageMonths: response.ageMonths, fromPersonId: response.fromPersonId, today: request.today)
        responses[Self.key(answered)] = response
        if request.includeAvailableAges {
            answered.includeAvailableAges = true
            responses[Self.key(answered)] = response
        }
    }

    func removeAll() {
        responses = [:]
    }
}

/// Loads one Same age answer for a record's strip. Never asks for age discovery, which scans the family's photo history. Offline with nothing cached, it says so rather than showing empty rows.
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

    private let fetch: SameAgeFetch
    private let cache: SameAgeCache

    init(apiClient: APIClient = .shared, cache: SameAgeCache? = nil) {
        self.fetch = apiClient.sameAgeFetch()
        self.cache = cache ?? .shared
    }

    /// `ageMonths` nil asks for the anchor's current age — or, with no anchor (0), the youngest own child's.
    func load(ageMonths: Int?, fromPersonId: Int, isConnected: Bool) async {
        let request = GetSameAgeRequestDTO(ageMonths: ageMonths, fromPersonId: fromPersonId, today: WhenEntry.localDateString(Date()))
        if let cached = cache.response(for: request) {
            state = .loaded(cached)
            return
        }
        guard isConnected else {
            state = .offline
            return
        }
        state = .loading
        do {
            let response = try await fetch(request)
            cache.store(response, for: request)
            state = .loaded(response)
        } catch {
            AppLog.ui.error("Same age failed: \(String(describing: error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

/// The browse page's state — a port of the web's `sameAgeNavigation`. The age the user asked for is tracked apart from the answer on screen, so the controls stay put while an age loads, a failure keeps the chosen age for Retry, and an answer that arrives after a newer choice is dropped.
@MainActor
@Observable
final class SameAgeBrowser {
    enum Failure: Equatable {
        case offline
        case failed
    }

    /// The ages the server found records at. Asked for once, on the first load, and kept while the page steps through ages with lightweight requests.
    struct Discovery: Equatable {
        let available: [SameAgeOptionDTO]
        let portraits: [SameAgeOptionDTO]
    }

    var mode: SameAgeMode
    /// The answer on screen.
    private(set) var response: GetSameAgeResponseDTO?
    /// Nil until the first answer, and from a server that predates discovery — then the page steps along the age grid as it used to.
    private(set) var discovery: Discovery?
    /// Everyone with a birthday who could be compared, from the first answer. Nil from an older server.
    private(set) var peopleCount: Int?
    /// The age last asked for. Nil only until the server picks one for a direct visit.
    private(set) var selectedAge: Int?
    private(set) var isLoading = false
    private(set) var failure: Failure?

    private let requestedAge: Int?
    private let requestedFrom: Int
    private let fetch: SameAgeFetch
    private let cache: SameAgeCache
    private let today: @MainActor () -> String
    /// Bumped by every load. An answer whose number is no longer current is somebody else's.
    private var generation = 0

    init(
        ageMonths: Int?,
        fromPersonId: Int,
        mode: SameAgeMode,
        fetch: SameAgeFetch? = nil,
        cache: SameAgeCache? = nil,
        today: @escaping @MainActor () -> String = { WhenEntry.localDateString(Date()) }
    ) {
        self.requestedAge = ageMonths
        self.requestedFrom = fromPersonId
        self.mode = mode
        self.selectedAge = ageMonths
        self.fetch = fetch ?? APIClient.shared.sameAgeFetch()
        self.cache = cache ?? .shared
        self.today = today
    }

    /// The person the comparison is about: the server's choice once it has answered, so stepping stays about the same person.
    private var anchor: Int { response?.fromPersonId ?? requestedFrom }

    /// The ages this view steps through — those with a portrait, or with any record — or nil when the server sent none to step through.
    var options: [SameAgeOptionDTO]? {
        discovery.map { mode == .portraits ? $0.portraits : $0.available }
    }

    /// The age the heading names: the one asked for after a failure, else the one answered.
    var headingAge: Int? {
        failure != nil ? selectedAge : response?.ageMonths ?? selectedAge
    }

    var younger: Int? { neighbour(-1) }
    var older: Int? { neighbour(1) }

    private func neighbour(_ direction: Int) -> Int? {
        guard let current = selectedAge else { return nil }
        if let options {
            return AgeSteps.nearbyAge(in: options.map(\.ageMonths), from: current, direction: direction)
        }
        // An older server: one step along the grid, between birth and the oldest age anyone has reached.
        if direction < 0 {
            return current > 0 ? AgeSteps.prevAge(current) : nil
        }
        let maxAge = response?.maxAgeMonths ?? 0
        return current < maxAge ? AgeSteps.nextAge(current, maxMonths: maxAge) : nil
    }

    /// The first load, with age discovery. A direct visit (no age, no person) lets the server pick the starting age for the view that is showing.
    func start(isConnected: Bool) async {
        let request = GetSameAgeRequestDTO(
            ageMonths: requestedAge,
            fromPersonId: requestedFrom,
            today: today(),
            includeAvailableAges: true,
            details: mode == .details
        )
        await load(request, discovering: true, isConnected: isConnected)
    }

    /// Pull to refresh: everything again, discovery included, at the age on screen.
    func refresh(isConnected: Bool) async {
        cache.removeAll()
        guard response != nil else {
            await start(isConnected: isConnected)
            return
        }
        let request = GetSameAgeRequestDTO(
            ageMonths: selectedAge,
            fromPersonId: anchor,
            today: today(),
            includeAvailableAges: true
        )
        await load(request, discovering: true, isConnected: isConnected)
    }

    /// Moves to an age. An explicitly chosen age is kept even when nobody has anything there.
    func select(_ age: Int, isConnected: Bool) async {
        if age == selectedAge && isLoading { return }
        if age == response?.ageMonths && !isLoading && failure == nil {
            selectedAge = age
            return
        }
        await load(lightweight(age), discovering: false, isConnected: isConnected)
    }

    /// Tries the chosen age again — or the first load, when nothing has loaded yet.
    func retry(isConnected: Bool) async {
        if response == nil {
            await start(isConnected: isConnected)
        } else if let selectedAge {
            await load(lightweight(selectedAge), discovering: false, isConnected: isConnected)
        }
    }

    private func lightweight(_ age: Int) -> GetSameAgeRequestDTO {
        GetSameAgeRequestDTO(ageMonths: age, fromPersonId: anchor, today: today())
    }

    private func load(_ request: GetSameAgeRequestDTO, discovering: Bool, isConnected: Bool) async {
        generation += 1
        let mine = generation
        if let age = request.ageMonths { selectedAge = age }
        failure = nil

        if let cached = cache.response(for: request) {
            isLoading = false
            apply(cached, discovering: discovering)
            return
        }
        guard isConnected else {
            isLoading = false
            failure = .offline
            return
        }

        isLoading = true
        do {
            let response = try await fetch(request)
            guard mine == generation else { return }
            cache.store(response, for: request)
            apply(response, discovering: discovering)
        } catch {
            guard mine == generation else { return }
            // A cancelled load is the view going away, not a failure to show it.
            if !Task.isCancelled {
                AppLog.ui.error("Same age failed: \(String(describing: error), privacy: .public)")
                failure = .failed
            }
        }
        isLoading = false
    }

    private func apply(_ response: GetSameAgeResponseDTO, discovering: Bool) {
        self.response = response
        selectedAge = response.ageMonths
        if discovering {
            if let available = response.availableAges, let portraits = response.portraitAges {
                discovery = Discovery(available: available, portraits: portraits)
            } else {
                discovery = nil
            }
            peopleCount = response.peopleCount
        } else if peopleCount == nil {
            peopleCount = response.peopleCount
        }
    }
}

import Foundation
import Testing
@testable import Family_Portal_Ios

/// A `GetSameAge` stand-in whose answers the test hands out one at a time, in whatever order it likes.
@MainActor
private final class HeldSameAge {
    private(set) var requests: [GetSameAgeRequestDTO] = []
    private var waiting: [CheckedContinuation<GetSameAgeResponseDTO, Error>] = []

    var fetch: SameAgeFetch {
        { request in
            self.requests.append(request)
            return try await withCheckedThrowingContinuation { self.waiting.append($0) }
        }
    }

    var pendingCount: Int { waiting.count }

    func answer(_ index: Int, with response: GetSameAgeResponseDTO) {
        waiting[index].resume(returning: response)
    }

    func fail(_ index: Int) {
        waiting[index].resume(throwing: URLError(.badServerResponse))
    }

    /// Lets the tasks the test started run until `count` requests are waiting.
    func waitFor(_ count: Int) async {
        while waiting.count < count { await Task.yield() }
    }
}

@MainActor
@Suite("Same age browsing")
struct SameAgeBrowserTests {

    private static let today = "2026-10-07"

    private func response(
        age: Int,
        from: Int = 4,
        available: [Int: Int]? = nil,
        portraits: [Int: Int]? = nil,
        peopleCount: Int? = 3
    ) throws -> GetSameAgeResponseDTO {
        var payload: [String: Any] = ["ageMonths": age, "fromPersonId": from, "maxAgeMonths": 120, "rows": []]
        func list(_ counts: [Int: Int]) -> [[String: Any]] {
            counts.keys.sorted().map { ["ageMonths": $0, "peopleCount": counts[$0]!] }
        }
        if let available { payload["availableAges"] = list(available) }
        if let portraits { payload["portraitAges"] = list(portraits) }
        if let peopleCount { payload["peopleCount"] = peopleCount }
        return try APIClient.decode(GetSameAgeResponseDTO.self, from: Fixture.data(payload))
    }

    private func browser(_ held: HeldSameAge, age: Int? = nil, from: Int = 0, mode: SameAgeMode = .portraits) -> SameAgeBrowser {
        SameAgeBrowser(ageMonths: age, fromPersonId: from, mode: mode, fetch: held.fetch, cache: SameAgeCache(), today: { Self.today })
    }

    /// Starts the first load and answers it.
    private func started(_ held: HeldSameAge, _ browser: SameAgeBrowser, with first: GetSameAgeResponseDTO) async {
        let start = Task { await browser.start(isConnected: true) }
        await held.waitFor(1)
        held.answer(0, with: first)
        await start.value
    }

    // MARK: - First load

    @Test("A direct visit asks for discovery and lets the server pick the age, for the view showing")
    func directVisit() async throws {
        let held = HeldSameAge()
        let browser = browser(held, mode: .details)
        await started(held, browser, with: try response(age: 6, available: [0: 1, 6: 3], portraits: [0: 1]))

        let request = try #require(held.requests.first)
        #expect(request.includeAvailableAges)
        #expect(request.details)
        #expect(request.ageMonths == nil)
        #expect(browser.selectedAge == 6)
        #expect(browser.headingAge == 6)
    }

    @Test("A link's age and person are asked for as given")
    func contextualVisit() async throws {
        let held = HeldSameAge()
        let browser = browser(held, age: 20, from: 4)
        await started(held, browser, with: try response(age: 20, available: [3: 2], portraits: [3: 2]))

        #expect(held.requests.first?.ageMonths == 20)
        #expect(held.requests.first?.fromPersonId == 4)
        // Kept although nothing is recorded there.
        #expect(browser.selectedAge == 20)
    }

    // MARK: - Stepping

    @Test("Younger and Older skip ages with nothing to show in the current view")
    func stepsAlongDiscoveredAges() async throws {
        let held = HeldSameAge()
        let browser = browser(held)
        await started(held, browser, with: try response(age: 12, available: [0: 2, 6: 1, 12: 3, 48: 2], portraits: [0: 2, 12: 3, 60: 1]))

        #expect(browser.younger == 0)
        #expect(browser.older == 60)
        browser.mode = .details
        #expect(browser.younger == 6)
        #expect(browser.older == 48)
    }

    @Test("A server without discovery steps along the age grid, as far as the oldest age reached")
    func olderServerSteps() async throws {
        let held = HeldSameAge()
        let browser = browser(held)
        await started(held, browser, with: try response(age: 24, peopleCount: nil))

        #expect(browser.discovery == nil)
        #expect(browser.options == nil)
        #expect(browser.younger == 23)
        #expect(browser.older == 27)
    }

    @Test("Discovery is kept while stepping through ages that never ask for it")
    func keepsDiscovery() async throws {
        let held = HeldSameAge()
        let browser = browser(held)
        await started(held, browser, with: try response(age: 12, available: [6: 1, 12: 3], portraits: [6: 1, 12: 3], peopleCount: 3))

        let step = Task { await browser.select(6, isConnected: true) }
        await held.waitFor(2)
        #expect(held.requests[1].includeAvailableAges == false)
        #expect(held.requests[1].fromPersonId == 4)
        // The controls stay on the chosen age while it loads.
        #expect(browser.selectedAge == 6)
        #expect(browser.isLoading)
        held.answer(1, with: try response(age: 6, available: [], portraits: [], peopleCount: 3))
        await step.value

        #expect(browser.response?.ageMonths == 6)
        #expect(browser.options?.map(\.ageMonths) == [6, 12])
        #expect(browser.peopleCount == 3)
    }

    @Test("An answer that arrives after a newer choice never replaces it")
    func staleAnswerDropped() async throws {
        let held = HeldSameAge()
        let browser = browser(held)
        await started(held, browser, with: try response(age: 12, available: [3: 1, 6: 1, 12: 1], portraits: [3: 1, 6: 1, 12: 1]))

        let first = Task { await browser.select(6, isConnected: true) }
        await held.waitFor(2)
        let second = Task { await browser.select(3, isConnected: true) }
        await held.waitFor(3)

        held.answer(2, with: try response(age: 3))
        await second.value
        held.answer(1, with: try response(age: 6))
        await first.value

        #expect(browser.response?.ageMonths == 3)
        #expect(browser.selectedAge == 3)
        #expect(browser.isLoading == false)
    }

    @Test("A failure keeps the chosen age, and Retry asks for it again")
    func failureKeepsAge() async throws {
        let held = HeldSameAge()
        let browser = browser(held)
        await started(held, browser, with: try response(age: 12, available: [6: 1, 12: 1], portraits: [6: 1, 12: 1]))

        let step = Task { await browser.select(6, isConnected: true) }
        await held.waitFor(2)
        held.fail(1)
        await step.value

        #expect(browser.failure == .failed)
        #expect(browser.selectedAge == 6)
        #expect(browser.headingAge == 6)
        // The last answer is still there to come back to.
        #expect(browser.response?.ageMonths == 12)

        let retry = Task { await browser.retry(isConnected: true) }
        await held.waitFor(3)
        #expect(held.requests[2].ageMonths == 6)
        held.answer(2, with: try response(age: 6))
        await retry.value
        #expect(browser.failure == nil)
        #expect(browser.response?.ageMonths == 6)
    }

    @Test("Offline, an age not opened before fails in place without asking")
    func offlineStep() async throws {
        let held = HeldSameAge()
        let browser = browser(held)
        await started(held, browser, with: try response(age: 12, available: [6: 1, 12: 1], portraits: [6: 1, 12: 1]))

        await browser.select(6, isConnected: false)
        #expect(browser.failure == .offline)
        #expect(held.requests.count == 1)
        #expect(browser.selectedAge == 6)
    }

    @Test("Choosing the age already on screen asks for nothing")
    func sameAgeNoFetch() async throws {
        let held = HeldSameAge()
        let browser = browser(held)
        await started(held, browser, with: try response(age: 12, available: [12: 1], portraits: [12: 1]))

        await browser.select(12, isConnected: true)
        #expect(held.requests.count == 1)
    }

    // MARK: - Cache

    @Test("A strip's answer never satisfies the browse page's first load")
    func lightweightDoesNotServeDiscovery() throws {
        let cache = SameAgeCache()
        let strip = GetSameAgeRequestDTO(ageMonths: 12, fromPersonId: 4, today: Self.today)
        cache.store(try response(age: 12), for: strip)

        let browse = GetSameAgeRequestDTO(ageMonths: 12, fromPersonId: 4, today: Self.today, includeAvailableAges: true)
        #expect(cache.response(for: browse) == nil)
        #expect(cache.response(for: strip) != nil)
    }

    @Test("A discovering answer serves a later lightweight ask for the age it settled on")
    func discoveryServesLightweight() throws {
        let cache = SameAgeCache()
        let browse = GetSameAgeRequestDTO(ageMonths: nil, fromPersonId: 0, today: Self.today, includeAvailableAges: true)
        cache.store(try response(age: 6, from: 4, available: [6: 2], portraits: [6: 2]), for: browse)

        #expect(cache.response(for: GetSameAgeRequestDTO(ageMonths: 6, fromPersonId: 4, today: Self.today))?.ageMonths == 6)
        // A strip's "now" for nobody in particular is a different question: the youngest child's current age.
        #expect(cache.response(for: GetSameAgeRequestDTO(ageMonths: nil, fromPersonId: 0, today: Self.today)) == nil)
        // Nor does the Portraits start answer the Details start.
        var details = browse
        details.details = true
        #expect(cache.response(for: details) == nil)
    }

    @Test("Yesterday's answers are not today's")
    func cacheIsPerDay() throws {
        let cache = SameAgeCache()
        cache.store(try response(age: 12), for: GetSameAgeRequestDTO(ageMonths: nil, fromPersonId: 4, today: "2026-10-06"))
        #expect(cache.response(for: GetSameAgeRequestDTO(ageMonths: nil, fromPersonId: 4, today: Self.today)) == nil)
    }
}

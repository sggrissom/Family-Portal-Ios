import Foundation
import OSLog

/// The search screen's state: what was typed, which understandings were switched off, and the latest answer.
/// Every change invalidates whatever is in flight, so a slow answer to an older query never replaces a newer one.
@Observable
final class SearchModel {
    typealias Fetch = @MainActor (SearchRequestDTO) async throws -> SearchResponseDTO

    /// Longer than the web's 150 ms, since a phone is often on cellular.
    static let debounce: Duration = .milliseconds(250)

    private(set) var query = ""
    private(set) var ignore: Set<SearchIgnore> = []
    private(set) var limit = 0
    /// The latest answer. Kept while the next one loads, so the screen doesn't flash empty between keystrokes.
    private(set) var response: SearchResponseDTO?
    private(set) var isLoading = false
    private(set) var failed = false
    /// Whether `response` answers exactly what is asked now — the words, the chips removed and the limit.
    private(set) var isCurrent = false

    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let fetch: Fetch

    init(debounce: Duration = SearchModel.debounce, fetch: @escaping Fetch) {
        delay = debounce
        self.fetch = fetch
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The answer, if it is for what is typed now.
    var currentResponse: SearchResponseDTO? {
        trimmedQuery.isEmpty ? nil : response
    }

    /// Typing: the understanding starts over, and the search runs once typing pauses.
    func type(_ text: String) {
        guard text != query else { return }
        query = text
        ignore = []
        limit = 0
        invalidate()
        let delay = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    /// Searching for something at once: a person chip, a recent search, the return key.
    func search(_ text: String) async {
        query = text
        ignore = []
        limit = 0
        invalidate()
        await run()
    }

    /// Removing a chip: the same words, with that kind of understanding off.
    func remove(_ kind: SearchIgnore) async {
        ignore.insert(kind)
        invalidate()
        await run()
    }

    func showAllMoments() async {
        limit = SearchResults.showAllMomentsLimit
        invalidate()
        await run()
    }

    /// Whatever is in flight or waiting is now out of date.
    private func invalidate() {
        pending?.cancel()
        pending = nil
        sequence += 1
        isCurrent = false
    }

    private func run() async {
        sequence += 1
        let mine = sequence
        let text = trimmedQuery
        guard !text.isEmpty else {
            response = nil
            isLoading = false
            failed = false
            isCurrent = true
            return
        }
        isLoading = true
        let request = SearchRequestDTO(
            query: text,
            ignore: ignore.isEmpty ? nil : ignore.map(\.rawValue).sorted(),
            limit: limit > 0 ? limit : nil
        )
        do {
            let answer = try await fetch(request)
            guard mine == sequence else { return }
            response = answer
            failed = false
            isCurrent = true
        } catch {
            guard mine == sequence else { return }
            AppLog.ui.error("Search failed: \(String(describing: error), privacy: .public)")
            failed = true
        }
        isLoading = false
    }
}

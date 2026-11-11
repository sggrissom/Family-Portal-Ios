import Foundation

/// The decisions behind **Find in your library**, kept apart from PhotoKit and Vision so they can be tested: which ages to offer, how a library splits into moments, which of a moment's photos to look at, and which one to suggest.
///
/// Everything runs on the device. Nothing leaves it until the user picks a photo and adds it, which is an ordinary import.
/// Dates are in **photo-date space** throughout — the capture's wall-clock time labelled UTC, as `Photo.photoDate` holds it — so a library photo and an app photo taken at the same moment compare equal.
nonisolated enum LibraryFinder {

    // MARK: - Age windows

    /// One stretch of someone's life to look for photos in: half-years until two, whole years after.
    struct AgeWindow: Identifiable, Hashable, Sendable {
        /// Months from birth, start inclusive and end exclusive.
        let fromMonth: Int
        let toMonth: Int
        let from: Date
        /// Clipped to today for the window they are in now.
        let to: Date

        var id: Int { fromMonth }

        var label: String {
            if toMonth <= 24 { return "\(fromMonth)–\(toMonth) months" }
            let years = fromMonth / 12
            return "\(years) years old"
        }
    }

    /// Every window from birth to today, youngest first. `birthday` is a record date, as `Person.birthday` holds it.
    static func windows(birthday: Date, now: Date = Date()) -> [AgeWindow] {
        let birth = birthday.recordDate
        let today = now.localWallClock()
        var windows: [AgeWindow] = []
        var start = 0
        // A hundred and twenty years is the most anybody gets.
        while start < 120 * 12 {
            let end = start < 24 ? start + 6 : start + 12
            guard let from = utc.date(byAdding: .month, value: start, to: birth), from < today,
                  let to = utc.date(byAdding: .month, value: end, to: birth)
            else { break }
            windows.append(AgeWindow(fromMonth: start, toMonth: end, from: from, to: min(to, today)))
            start = end
        }
        return windows
    }

    /// How many of `dates` fall inside `window`: how well the app already covers that age.
    static func count(of dates: [Date], in window: AgeWindow) -> Int {
        dates.reduce(0) { $0 + ($1 >= window.from && $1 < window.to ? 1 : 0) }
    }

    /// Whether a window ended before the library's first photo, so the library can't fill it. A library with no photos reaches nothing.
    static func isBeforeLibrary(_ window: AgeWindow, start: Date?) -> Bool {
        guard let start else { return true }
        return window.to <= start
    }

    // MARK: - Coverage map

    /// Birth to eighteen, the ages the family map lines up: four half-years, then a year at a time.
    static func childhood(_ windows: [AgeWindow]) -> [AgeWindow] {
        windows.filter { $0.fromMonth <= 18 * 12 }
    }

    /// Columns in a complete childhood: 0–24 months in four, then 2 through 18.
    static let childhoodColumns = 4 + 17

    /// The age labels over the map's columns.
    struct AxisMark: Hashable, Sendable {
        let column: Int
        let label: String
    }

    static let axisMarks: [AxisMark] = [(0, "0"), (2, "1"), (4, "2"), (7, "5"), (12, "10"), (17, "15"), (20, "18")]
        .map { AxisMark(column: $0.0, label: $0.1) }

    enum Coverage: Equatable {
        case empty, few, several, many
    }

    static func coverage(_ count: Int) -> Coverage {
        switch count {
        case 0: .empty
        case 1...2: .few
        case 3...9: .several
        default: .many
        }
    }

    /// The device instant for a wall-clock time in the current zone: the inverse of `localWallClock`, for asking PhotoKit, which compares instants.
    static func instant(fromWallClock date: Date, in timeZone: TimeZone = .current) -> Date {
        date.addingTimeInterval(-Double(timeZone.secondsFromGMT(for: date)))
    }

    // MARK: - Library photos

    /// What the finder needs to know about one library photo, read once from its `PHAsset`.
    struct Asset: Identifiable, Hashable, Sendable {
        /// `PHAsset.localIdentifier`.
        let id: String
        let date: Date
        let isFavorite: Bool
        var latitude: Double? = nil
        var longitude: Double? = nil
    }

    /// Photos taken together: a birthday party, a morning at the beach. The finder suggests one photo from each, so forty shots of the same cake become one.
    struct Moment: Sendable {
        var assets: [Asset]
    }

    /// A gap longer than this starts a new moment.
    static let momentGap: TimeInterval = 45 * 60
    /// So does moving further than this, when both photos know where they were taken.
    static let momentDistance: Double = 2_000

    static func moments(_ assets: [Asset]) -> [Moment] {
        var moments: [Moment] = []
        for asset in assets.sorted(by: { $0.date < $1.date }) {
            if let previous = moments.last?.assets.last, !startsNewMoment(asset, after: previous) {
                moments[moments.count - 1].assets.append(asset)
            } else {
                moments.append(Moment(assets: [asset]))
            }
        }
        return moments
    }

    static func startsNewMoment(_ asset: Asset, after previous: Asset) -> Bool {
        if asset.date.timeIntervalSince(previous.date) > momentGap { return true }
        if let lat1 = previous.latitude, let lon1 = previous.longitude,
           let lat2 = asset.latitude, let lon2 = asset.longitude,
           metres(lat1, lon1, lat2, lon2) > momentDistance {
            return true
        }
        return false
    }

    /// Great-circle distance; close enough for telling one place from another.
    private static func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// The photos of a moment worth analysing: every favourite, plus up to `limit` spread evenly from its first to its last. Analysing every photo of a long day is what makes a search slow; a spread finds the good ones almost as often.
    static func sample(_ moment: Moment, limit: Int = 4) -> [Asset] {
        let assets = moment.assets
        var picked = assets.filter(\.isFavorite)
        if assets.count <= limit {
            picked += assets
        } else {
            for step in 0..<limit {
                picked.append(assets[step * (assets.count - 1) / (limit - 1)])
            }
        }
        var seen = Set<String>()
        return picked.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Choosing

    /// What Vision says about one photo. Faces are *detected*, never recognised: the finder knows a photo has people in it, not who.
    struct Analysis: Sendable, Equatable {
        var faceCount = 0
        /// 0…1, the capture quality of the best face (sharp, eyes open, facing the camera); 0 with no faces.
        var bestFaceQuality: Float = 0
        /// The share of the image the largest face covers, 0…1.
        var largestFaceArea: Float = 0
        /// Vision's overall aesthetic score, −1…1.
        var aesthetics: Float = 0
        /// A receipt, a whiteboard, a screenshot of something: kept for its information, not as a memory.
        var isUtility = false
    }

    /// A moment's best photo, offered for review.
    struct Candidate: Identifiable, Sendable, Equatable {
        let asset: Asset
        /// How many photos the moment had: "best of 12".
        let momentSize: Int
        let score: Double

        var id: String { asset.id }
    }

    static func score(_ asset: Asset, _ analysis: Analysis) -> Double {
        var score = Double(analysis.aesthetics)
        if asset.isFavorite { score += 1 }
        if analysis.faceCount > 0 {
            score += 0.6
            score += Double(analysis.bestFaceQuality) * 0.6
            score += min(Double(analysis.largestFaceArea) * 4, 0.4)
        }
        return score
    }

    /// The finder looks for photos of people. A favourite is always worth a look; anything else needs a face and must not be a utility shot.
    static func isWorthSuggesting(_ asset: Asset, _ analysis: Analysis) -> Bool {
        asset.isFavorite || (analysis.faceCount > 0 && !analysis.isUtility)
    }

    /// The moment's highest-scoring sampled photo that is worth suggesting, or nil when none is.
    static func best(of moment: Moment, analyses: [String: Analysis]) -> Candidate? {
        sample(moment)
            .compactMap { asset -> Candidate? in
                guard let analysis = analyses[asset.id], isWorthSuggesting(asset, analysis) else { return nil }
                return Candidate(asset: asset, momentSize: moment.assets.count, score: score(asset, analysis))
            }
            .max { $0.score < $1.score }
    }

    // MARK: - Already in the app

    /// Which library photos the app already has: by `Photo.libraryAssetId` where an import recorded one, otherwise by capture time to the second.
    /// The time match covers photos imported before the id was kept, or on another device. A photo whose date was set to a day rather than a moment (midnight) is left out of it: it would match nothing real and could match the wrong thing.
    struct ImportedIndex: Sendable {
        private var assetIds: Set<String> = []
        private var seconds: Set<Int> = []

        init(assetIds: some Sequence<String>, captureTimes: some Sequence<Date>) {
            self.assetIds = Set(assetIds)
            for time in captureTimes where !time.isUTCMidnight {
                seconds.insert(Int(time.timeIntervalSince1970.rounded()))
            }
        }

        func contains(_ asset: Asset) -> Bool {
            if assetIds.contains(asset.id) { return true }
            let second = Int(asset.date.timeIntervalSince1970.rounded())
            return seconds.contains(second) || seconds.contains(second - 1) || seconds.contains(second + 1)
        }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}

/// Library photos the user said not to suggest again, per person: "not Emma" is not "not anybody". Device-local, like the asset ids it holds, and erased with the account's other local data.
nonisolated struct LibraryFinderSkips {
    static let key = "libraryFinder.skipped"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func skipped(for personId: UUID) -> Set<String> {
        Set(all()[personId.uuidString] ?? [])
    }

    func skip(_ assetId: String, for personId: UUID) {
        var all = all()
        var ids = all[personId.uuidString] ?? []
        guard !ids.contains(assetId) else { return }
        ids.append(assetId)
        all[personId.uuidString] = ids
        defaults.set(all, forKey: Self.key)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    private func all() -> [String: [String]] {
        defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
    }
}

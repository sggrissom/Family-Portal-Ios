import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Library finder")
struct LibraryFinderTests {

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func asset(_ id: String, _ date: Date, favorite: Bool = false, at place: (Double, Double)? = nil) -> LibraryFinder.Asset {
        LibraryFinder.Asset(id: id, date: date, isFavorite: favorite, latitude: place?.0, longitude: place?.1)
    }

    // MARK: - Age windows

    @Test("Half-years until two, then whole years, up to today")
    func windowsSplitByAge() {
        let windows = LibraryFinder.windows(birthday: day(2020, 3, 15), now: day(2024, 9, 1, 12))

        #expect(windows.map(\.label) == [
            "0–6 months", "6–12 months", "12–18 months", "18–24 months",
            "2 years old", "3 years old", "4 years old",
        ])
        #expect(windows[0].from == day(2020, 3, 15))
        #expect(windows[1].from == day(2020, 9, 15))
        #expect(windows[4].from == day(2022, 3, 15))
        #expect(windows[4].to == day(2023, 3, 15))
    }

    @Test("The window someone is in now ends today")
    func currentWindowIsClipped() throws {
        let now = day(2024, 9, 1, 12)
        let last = try #require(LibraryFinder.windows(birthday: day(2020, 3, 15), now: now).last)

        #expect(last.to == now.localWallClock())
    }

    @Test("A birthday in the future has no windows")
    func futureBirthdayHasNone() {
        #expect(LibraryFinder.windows(birthday: day(2030, 1, 1), now: day(2026, 1, 1)).isEmpty)
    }

    @Test("Counting app photos is start-inclusive and end-exclusive")
    func countsByWindow() throws {
        let window = try #require(LibraryFinder.windows(birthday: day(2020, 3, 15), now: day(2024, 1, 1)).first)
        let dates = [day(2020, 3, 15), day(2020, 6, 1, 9), day(2020, 9, 15), day(2019, 1, 1)]

        #expect(LibraryFinder.count(of: dates, in: window) == 2)
    }

    // MARK: - Moments

    @Test("A long gap starts a new moment")
    func gapSplitsMoments() {
        let moments = LibraryFinder.moments([
            asset("c", day(2021, 5, 1, 15)),
            asset("a", day(2021, 5, 1, 10)),
            asset("b", day(2021, 5, 1, 10, 30)),
        ])

        #expect(moments.map { $0.assets.map(\.id) } == [["a", "b"], ["c"]])
    }

    @Test("Moving somewhere else starts a new moment, even soon after")
    func distanceSplitsMoments() {
        let moments = LibraryFinder.moments([
            asset("home", day(2021, 5, 1, 10), at: (40.0, -75.0)),
            asset("park", day(2021, 5, 1, 10, 20), at: (40.1, -75.0)),
            asset("park2", day(2021, 5, 1, 10, 25), at: (40.1001, -75.0)),
            asset("nowhere", day(2021, 5, 1, 10, 30)),
        ])

        #expect(moments.map { $0.assets.map(\.id) } == [["home"], ["park", "park2", "nowhere"]])
    }

    @Test("A sample spreads across the moment and always includes favourites")
    func sampleSpreadsAndKeepsFavourites() {
        let assets = (0..<10).map { asset("\($0)", day(2021, 5, 1, 10, $0), favorite: $0 == 5) }
        let sample = LibraryFinder.sample(LibraryFinder.Moment(assets: assets))

        #expect(sample.map(\.id) == ["5", "0", "3", "6", "9"])
    }

    @Test("A small moment is sampled whole, once")
    func smallMomentSampledWhole() {
        let assets = [asset("a", day(2021, 5, 1), favorite: true), asset("b", day(2021, 5, 1, 0, 1))]

        #expect(LibraryFinder.sample(LibraryFinder.Moment(assets: assets)).map(\.id) == ["a", "b"])
    }

    // MARK: - Choosing

    @Test("The best is the sampled photo with the clearest face, and a moment of scenery offers nothing")
    func bestPrefersFaces() {
        let moment = LibraryFinder.Moment(assets: [
            asset("view", day(2021, 5, 1, 10)),
            asset("blurry", day(2021, 5, 1, 10, 1)),
            asset("sharp", day(2021, 5, 1, 10, 2)),
        ])
        let analyses: [String: LibraryFinder.Analysis] = [
            "view": .init(faceCount: 0, aesthetics: 0.9),
            "blurry": .init(faceCount: 1, bestFaceQuality: 0.2, largestFaceArea: 0.05, aesthetics: 0.1),
            "sharp": .init(faceCount: 1, bestFaceQuality: 0.8, largestFaceArea: 0.05, aesthetics: 0.1),
        ]

        let best = LibraryFinder.best(of: moment, analyses: analyses)
        #expect(best?.id == "sharp")
        #expect(best?.momentSize == 3)

        let scenery = LibraryFinder.Moment(assets: [asset("view", day(2021, 5, 1, 10))])
        #expect(LibraryFinder.best(of: scenery, analyses: analyses) == nil)
    }

    @Test("A utility shot isn't suggested, unless it's a favourite")
    func utilityLeftOut() {
        let receipt = asset("r", day(2021, 5, 1))
        let utility = LibraryFinder.Analysis(faceCount: 1, isUtility: true)

        #expect(!LibraryFinder.isWorthSuggesting(receipt, utility))
        #expect(LibraryFinder.isWorthSuggesting(asset("r", day(2021, 5, 1), favorite: true), utility))
    }

    // MARK: - Already in the app

    @Test("A library photo is already in the app by its asset id, or by its capture time to the second")
    func importedByIdOrTime() {
        let index = LibraryFinder.ImportedIndex(
            assetIds: ["known"],
            captureTimes: [day(2021, 5, 1, 10, 30).addingTimeInterval(7)]
        )

        #expect(index.contains(asset("known", day(2000, 1, 1, 1))))
        #expect(index.contains(asset("other", day(2021, 5, 1, 10, 30).addingTimeInterval(8))))
        #expect(!index.contains(asset("other", day(2021, 5, 1, 10, 30).addingTimeInterval(20))))
    }

    /// A photo re-dated to a day sits at midnight; matching on that would hide an unrelated photo taken at midnight.
    @Test("A photo dated only to a day matches nothing by time")
    func midnightIgnored() {
        let index = LibraryFinder.ImportedIndex(assetIds: [String](), captureTimes: [day(2021, 5, 1)])

        #expect(!index.contains(asset("x", day(2021, 5, 1))))
    }

    // MARK: - Skips

    @Test("Skips are per person and erased with the rest")
    func skipsPerPerson() throws {
        let defaults = try #require(UserDefaults(suiteName: "LibraryFinderTests-\(UUID().uuidString)"))
        let skips = LibraryFinderSkips(defaults: defaults)
        let emma = UUID()
        let dad = UUID()

        skips.skip("a", for: emma)
        skips.skip("a", for: emma)
        skips.skip("b", for: emma)

        #expect(skips.skipped(for: emma) == ["a", "b"])
        #expect(skips.skipped(for: dad).isEmpty)

        LibraryFinderSkips.clear(in: defaults)
        #expect(skips.skipped(for: emma).isEmpty)
    }
}

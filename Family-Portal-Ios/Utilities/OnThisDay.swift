import Foundation

/// The dashboard's "On this day", computed from the store for any day — the port of `onThisDay` in `backend/dashboard.go`, so a widget filled a week ahead shows what Home will show that morning.
///
/// For each of the last 30 years: the same calendar day **±2 days**, the newest eight photos in that window and every milestone in it. Years with neither are left out.
nonisolated enum OnThisDay {

    static let spreadDays = 2
    static let maxYears = 30
    static let photosPerYear = 8

    struct Year<Photo, Milestone> {
        var yearsAgo: Int
        var photos: [Photo]
        var milestones: [Milestone]
    }

    /// Records arrive with their record day already keyed (`recordDayKey`), so this never touches a time zone.
    /// `photoOrder` sorts newest first the way the server's photo index does: by capture time, then by id.
    static func years<Photo, Milestone>(
        on today: String,
        photos: [Photo],
        photoDay: (Photo) -> String,
        newerPhoto: (Photo, Photo) -> Bool,
        milestones: [Milestone],
        milestoneDay: (Milestone) -> String
    ) -> [Year<Photo, Milestone>] {
        guard let anchor = components(today) else { return [] }

        let photosByDay = Dictionary(grouping: photos, by: photoDay)
        let milestonesByDay = Dictionary(grouping: milestones, by: milestoneDay)

        var years: [Year<Photo, Milestone>] = []
        for yearsAgo in 1...maxYears {
            let days = window(around: anchor, yearsAgo: yearsAgo)
            let found = days.flatMap { photosByDay[$0] ?? [] }
                .sorted(by: newerPhoto)
                .prefix(photosPerYear)
            let said = days.flatMap { milestonesByDay[$0] ?? [] }
            if !found.isEmpty || !said.isEmpty {
                years.append(Year(yearsAgo: yearsAgo, photos: Array(found), milestones: said))
            }
        }
        return years
    }

    /// The five day keys around `anchor` moved back `yearsAgo` years, oldest first.
    /// The year is moved the way Go's `AddDate(-n, 0, 0)` moves it: 29 February in a common year *normalises* to 1 March rather than clamping to the 28th, so the window here and on Home agree.
    static func window(around today: String, yearsAgo: Int) -> [String] {
        guard let anchor = components(today) else { return [] }
        return window(around: anchor, yearsAgo: yearsAgo)
    }

    private static func window(around anchor: DateComponents, yearsAgo: Int) -> [String] {
        var moved = anchor
        moved.year = (anchor.year ?? 0) - yearsAgo
        // `date(from:)` is lenient: day 29 of a 28-day February rolls over into March, which is Go's normalisation.
        guard let center = utc.date(from: moved) else { return [] }
        return (-spreadDays...spreadDays).compactMap { offset in
            utc.date(byAdding: .day, value: offset, to: center).map(key)
        }
    }

    private static func components(_ day: String) -> DateComponents? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func key(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}

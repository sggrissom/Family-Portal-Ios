import Foundation

/// One person's measurements on one day, as a single row. `extra` counts readings past the first height and weight.
struct DayCheckup: Identifiable {
    let personId: UUID
    var height: GrowthData?
    var weight: GrowthData?
    var extra = 0

    var id: UUID { personId }
}

/// The day's remaining photos as one mosaic: the newest four, how many there are, and who is in them.
struct DayPhotoGroup {
    var count = 0
    var mosaicIds: [UUID] = []
    var allIds: [UUID] = []
    var personIds: [UUID] = []
}

struct DayBirthday: Equatable {
    let personId: UUID
    let age: Int
}

/// One event's appearances on a day — one card, with the family's results.
struct DayEvent: Identifiable {
    let event: EventSummaryDTO
    var appearances: [TimelineAppearanceDTO]

    var id: Int { event.id }
}

/// Everything recorded on one calendar day, grouped for display — a port of `DaySummary` in frontend/lib/daySummary.ts.
struct DaySummary: Identifiable {
    /// `YYYY-MM-DD`, the day each record names (`Date.recordDayKey`).
    let day: String
    var birthdays: [DayBirthday] = []
    var milestones: [Milestone] = []
    var events: [DayEvent] = []
    var checkups: [DayCheckup] = []
    var photos: DayPhotoGroup?

    var id: String { day }
}

/// What `summarize` groups. Appearances are the server's (`GetFamilyTimeline` with `includeActivities`); everything else is from the store.
struct DayRecords {
    var photos: [Photo] = []
    var growth: [GrowthData] = []
    var milestones: [Milestone] = []
    var appearances: [TimelineAppearanceDTO] = []
}

struct MonthGroup: Identifiable {
    /// `YYYY-MM`.
    let month: String
    let label: String
    var days: [DaySummary]

    var id: String { month }
}

/// Groups records into days — a port of frontend/lib/daySummary.ts, with the web's fixture cases in `DaySummaryTests`, so History, Story and Home group the same records the same way on both clients.
enum DaySummaries {

    static let mosaicSize = 4

    /// Every day's summary, newest first. With a `range`, birthdays inside it are added, even on otherwise quiet days.
    /// Photos attached to a milestone or an event in `records` are left out of the mosaics: the card already shows them.
    static func summarize(
        _ records: DayRecords,
        people: [Person],
        range: (from: String, to: String)? = nil
    ) -> [DaySummary] {
        var days: [String: DaySummary] = [:]
        func edit(_ day: String, _ change: (inout DaySummary) -> Void) {
            var summary = days[day] ?? DaySummary(day: day)
            change(&summary)
            days[day] = summary
        }

        if let range {
            for (day, birthdays) in birthdaysBetween(people, from: range.from, to: range.to) {
                edit(day) { $0.birthdays = birthdays }
            }
        }

        var attachedPhotoIds = Set<Int>()
        for milestone in records.milestones {
            attachedPhotoIds.formUnion(milestone.photoRemoteIds)
            edit(milestone.date.recordDayKey) { $0.milestones.append(milestone) }
        }

        for appearance in records.appearances {
            let detail = appearance.detail
            attachedPhotoIds.formUnion(detail.photoIds)
            let when = detail.appearance.occurredAt.serverDate ?? detail.event.startDate
            guard !when.isServerZero else { continue }
            edit(when.recordDayKey) { summary in
                if let index = summary.events.firstIndex(where: { $0.event.id == detail.event.id }) {
                    summary.events[index].appearances.append(appearance)
                } else {
                    summary.events.append(DayEvent(event: detail.event, appearances: [appearance]))
                }
            }
        }

        let newestGrowth = records.growth.sorted {
            $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString > $1.id.uuidString
        }
        for growth in newestGrowth {
            guard let personId = growth.person?.id else { continue }
            edit(growth.date.recordDayKey) { summary in
                var checkup = summary.checkups.first { $0.personId == personId } ?? DayCheckup(personId: personId)
                switch growth.measurementType {
                case .height:
                    if checkup.height == nil { checkup.height = growth } else { checkup.extra += 1 }
                case .weight:
                    if checkup.weight == nil { checkup.weight = growth } else { checkup.extra += 1 }
                }
                if let index = summary.checkups.firstIndex(where: { $0.personId == personId }) {
                    summary.checkups[index] = checkup
                } else {
                    summary.checkups.append(checkup)
                }
            }
        }

        let newestPhotos = records.photos
            .filter { photo in
                guard let remoteId = photo.serverId else { return true }
                return !attachedPhotoIds.contains(remoteId)
            }
            .sorted { $0.photoDate != $1.photoDate ? $0.photoDate > $1.photoDate : $0.id.uuidString > $1.id.uuidString }
        for photo in newestPhotos {
            edit(photo.photoDate.recordDayKey) { summary in
                var group = summary.photos ?? DayPhotoGroup()
                group.count += 1
                group.allIds.append(photo.id)
                if group.mosaicIds.count < mosaicSize { group.mosaicIds.append(photo.id) }
                for person in photo.taggedPeople where !group.personIds.contains(person.id) {
                    group.personIds.append(person.id)
                }
                summary.photos = group
            }
        }

        return days.values.sorted { $0.day > $1.day }
    }

    /// Each day in the range someone turns a year older. Pregnancies and the day of birth itself are skipped.
    static func birthdaysBetween(
        _ people: [Person],
        from: String,
        to: String
    ) -> [String: [DayBirthday]] {
        let born: [(Person, DateComponents)] = people.compactMap { person in
            guard !person.isPregnancy, let birthday = person.birthday else { return nil }
            return (person, birthday.recordDay)
        }
        guard !born.isEmpty else { return [:] }

        var byDay: [String: [DayBirthday]] = [:]
        for day in eachDay(from: from, to: to) {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            for (person, birth) in born {
                let age = parts[0] - (birth.year ?? 0)
                guard age > 0, birth.month == parts[1], birth.day == parts[2] else { continue }
                byDay[day, default: []].append(DayBirthday(personId: person.id, age: age))
            }
        }
        return byDay
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// The UTC midnight a day key names.
    static func date(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func eachDay(from: String, to: String) -> [String] {
        guard var cursor = Self.date(of: from), let end = Self.date(of: to) else { return [] }
        var days: [String] = []
        while cursor <= end {
            days.append(cursor.recordDayKey)
            guard let next = utc.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// "Today", "Yesterday", "Saturday, Sep 19", and the year when it is not this one — `dayLabel`.
    static func dayLabel(_ day: String, today: String) -> String {
        guard let shown = Self.date(of: day), let now = Self.date(of: today) else { return day }
        let diff = Int((now.timeIntervalSince(shown) / 86_400).rounded())
        if diff == 0 { return "Today" }
        if diff == 1 { return "Yesterday" }
        let parts = utc.dateComponents([.year, .month, .day, .weekday], from: shown)
        let label = "\(weekdays[(parts.weekday ?? 1) - 1]), \(shortMonths[(parts.month ?? 1) - 1]) \(parts.day ?? 0)"
        return parts.year == utc.component(.year, from: now) ? label : "\(label), \(parts.year ?? 0)"
    }

    /// Consecutive days under their month, in the order given — `groupByMonth`.
    static func groupByMonth(_ days: [DaySummary]) -> [MonthGroup] {
        var groups: [MonthGroup] = []
        for day in days {
            let month = String(day.day.prefix(7))
            if groups.last?.month == month {
                groups[groups.count - 1].days.append(day)
            } else {
                let parts = month.split(separator: "-").compactMap { Int($0) }
                let label = parts.count == 2 ? "\(monthNames[parts[1] - 1]) \(parts[0])" : month
                groups.append(MonthGroup(month: month, label: label, days: [day]))
            }
        }
        return groups
    }
}

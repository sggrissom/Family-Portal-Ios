import Foundation
import SwiftData

/// Rewrites dates stored before record dates were held as midnight UTC (see `Date.recordDay`). Each is read the way earlier builds read it: an exact UTC midnight as its UTC day, anything else in the device's zone.
/// A synced photo keeps its date, which the server sent as a UTC-labelled wall clock; one never uploaded holds a device instant and becomes its local wall clock.
enum CalendarDateMigration {
    static let defaultsKey = "com.familyrecord.calendarDatesMigrated"

    static func runIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: defaultsKey) else { return }
        do {
            try migrate(context)
            defaults.set(true, forKey: defaultsKey)
        } catch {
            AppLog.sync.error("Calendar date migration failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func migrate(_ context: ModelContext, timeZone: TimeZone = .current) throws {
        for person in try context.fetch(FetchDescriptor<Person>()) {
            if let birthday = person.birthday, let migrated = legacyRecordDate(birthday, in: timeZone) {
                person.birthday = migrated
            }
        }
        for record in try context.fetch(FetchDescriptor<GrowthData>()) {
            if let migrated = legacyRecordDate(record.date, in: timeZone) {
                record.date = migrated
            }
        }
        for milestone in try context.fetch(FetchDescriptor<Milestone>()) {
            if let migrated = legacyRecordDate(milestone.date, in: timeZone) {
                milestone.date = migrated
            }
        }
        for photo in try context.fetch(FetchDescriptor<Photo>()) where photo.remoteId == nil && !photo.photoDate.isUTCMidnight {
            photo.photoDate = photo.photoDate.localWallClock(in: timeZone)
        }
        try context.save()
    }

    /// `nil` when the date is already a record date.
    static func legacyRecordDate(_ date: Date, in timeZone: TimeZone) -> Date? {
        date.isUTCMidnight ? nil : date.localRecordDay(in: timeZone)
    }
}

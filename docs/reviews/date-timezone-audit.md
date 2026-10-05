# iOS date/timezone review

Reviewed main at `6c3f6c7` following the web repository's timezone audit.

Fixed remaining bypasses of the existing calendar-day helpers:

- Bare API dates now decode in UTC, matching Z-suffixed server dates.
- Activity date writes preserve server days, and activity, milestone, measurement,
  and batch-photo editors normalize dates for their local date pickers.
- Record labels use the intended calendar day. Photo detail omits the misleading
  local clock time for UTC-midnight calendar dates; other photo times retain
  their existing local timestamp display.
- Growth ages normalize mixed local birthdays and UTC measurement dates.
- Measurement recency counts calendar days across DST, rather than elapsed hours.
- Local photo filtering compares the photo's calendar day to the selected range.
- Photo upload date serialization uses the existing day-key helper instead of an
  unpinned date formatter (which could also use a non-Gregorian user calendar).

Existing safeguards include explicit device-local today/yesterday requests,
UTC-midnight-aware day keys, and local chat timestamp grouping. No chat timestamp
or creation-time decoding behavior was changed.

## Explicit calendar-date storage (follow-up)

The `isUTCMidnight` heuristic is gone. Every day is now held as a *record date*:
midnight UTC of the day it names, matching what the server stores. Photo dates
are the capture's local wall clock labelled UTC, which is also how the server now
stores EXIF times, so their UTC components are the capture day on both clients.

- `recordDay` / `recordDayKey` read a record date's UTC components; `displayDay()`
  turns one into local midnight for formatting, pickers and `Calendar.current`.
- `localRecordDay()` converts device instants (`Date()`, picker values) at the
  edge: `WhenEntry.resolvedDate`, the edit views, new people, activity date
  fields. `localWallClock()` does the same for photos captured on the device.
- Server values pass through `recordDate`, so a legacy server date carrying a
  time is stored as its UTC day, as the web shows it.
- Utilities that took a `timeZone` to second-guess their inputs (`AgeSteps`,
  `FamilyStrip`, `DaySummaries`, `GrowthPercentiles.ageInMonths`) now take record
  dates only; callers pass `Date().localRecordDay()` for today.
- `CalendarDateMigration` runs once at launch. It reads each stored value the way
  earlier builds did (an exact UTC midnight as its UTC day, anything else in the
  device's zone) and rewrites it as a record date. A synced photo keeps the
  server's value, and an unsynced one becomes its local wall clock.
- A queued photo upload now sends the model's (migrated) date rather than the
  instant captured in its queue payload.

Remaining: a value saved locally by an earlier build in one zone and migrated
after the device moved zones is read in the new zone, once. Synced records are
replaced by the server's values on the next pull.

## Validation

Added parameterized Swift Testing cases for unchanged activity write round-trips,
picker day components, bare-date decoding, growth ages, and DST recency across
UTC, Chicago, Los Angeles, Tokyo, and Kiritimati. `git diff --check` passes.
This Linux workspace has neither Swift nor Xcode; simulator build/tests must run
in the existing macOS GitHub Actions workflow before merging.

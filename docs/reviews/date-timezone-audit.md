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

## Limits and follow-up

The model still represents both calendar dates and timestamps as `Date`. Its
existing `isUTCMidnight` heuristic cannot distinguish a genuine instant exactly
at UTC midnight from a date-only server value. Locally persisted midnight values
also lose their original calendar-day meaning if the device changes timezone.
A complete solution needs explicit date-only storage and a migration strategy;
this patch reuses the current convention and does not migrate stored records.

Photo capture timestamps without a capture timezone cannot reliably reconstruct
the original local date after travel. Non-midnight legacy server record dates
continue to follow the existing local-day convention, which can differ from the
web's UTC photo-day convention. These are not claimed resolved by this patch.

## Validation

Added parameterized Swift Testing cases for unchanged activity write round-trips,
picker day components, bare-date decoding, growth ages, and DST recency across
UTC, Chicago, Los Angeles, Tokyo, and Kiritimati. `git diff --check` passes.
This Linux workspace has neither Swift nor Xcode; simulator build/tests must run
in the existing macOS GitHub Actions workflow before merging.

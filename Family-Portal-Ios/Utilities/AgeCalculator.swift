import Foundation

/// How old someone is, as a phrase. A port of `calculateAgeAt` and `calculateGestationalAgeAt` in `backend/person.go`, mirroring its arithmetic step for step.
/// Not `Calendar.dateComponents`, which resolves "31 March plus one month" by clamping to 30 April and calling it a whole month where the server calls it none.
enum AgeCalculator {

    static func age(from birthdate: Date, isPregnancy: Bool = false) -> String {
        age(from: birthdate, at: Date(), isPregnancy: isPregnancy)
    }

    static func age(from birthdate: Date, at referenceDate: Date, isPregnancy: Bool = false) -> String {
        // A record flagged as a pregnancy stays in weeks even once the due date has passed — an overdue baby is 41 weeks, not a day old.
        if isPregnancy || referenceDate < birthdate {
            return gestationalAge(dueDate: birthdate, at: referenceDate)
        }

        let calendar = Calendar.current
        let birth = calendar.dateComponents([.year, .month, .day], from: birthdate)
        let now = calendar.dateComponents([.year, .month, .day], from: referenceDate)

        guard let birthYear = birth.year, let birthMonth = birth.month, let birthDay = birth.day,
              let nowYear = now.year, let nowMonth = now.month, let nowDay = now.day
        else {
            return "< 1 month"
        }

        var years = nowYear - birthYear
        var months = nowMonth - birthMonth
        let days = nowDay - birthDay

        // The birthday has not come round yet this year.
        if months < 0 || (months == 0 && days < 0) {
            years -= 1
            months += 12
        }

        // The day of the month has not come round yet this month.
        if days < 0 {
            months -= 1
            if months < 0 {
                years -= 1
                months += 12
            }
        }

        if years == 0 {
            if months <= 0 {
                return "< 1 month"
            }
            return months == 1 ? "1 month" : "\(months) months"
        }

        return years == 1 ? "1 year" : "\(years) years"
    }

    /// Weeks of gestation, counting back from a 40-week term, over whole calendar days.
    private static func gestationalAge(dueDate: Date, at referenceDate: Date) -> String {
        let calendar = Calendar.current
        let due = calendar.startOfDay(for: dueDate)
        let reference = calendar.startOfDay(for: referenceDate)
        let daysUntilDue = calendar.dateComponents([.day], from: reference, to: due).day ?? 0

        var weeksPregnant = 40 - Int((Double(daysUntilDue) / 7.0).rounded(.up))
        if weeksPregnant < 0 {
            weeksPregnant = 0
        }
        return weeksPregnant == 1 ? "1 week" : "\(weeksPregnant) weeks"
    }
}

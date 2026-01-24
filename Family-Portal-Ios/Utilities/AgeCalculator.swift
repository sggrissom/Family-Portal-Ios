import Foundation

enum AgeCalculator {
    static func age(from birthdate: Date) -> String {
        age(from: birthdate, at: Date())
    }

    static func age(from birthdate: Date, at referenceDate: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: birthdate, to: referenceDate)

        let years = components.year ?? 0
        let months = components.month ?? 0

        if years < 1 {
            if months < 1 {
                return "< 1 month"
            } else if months == 1 {
                return "1 month"
            } else {
                return "\(months) months"
            }
        } else if years == 1 {
            return "1 year"
        } else {
            return "\(years) years"
        }
    }
}

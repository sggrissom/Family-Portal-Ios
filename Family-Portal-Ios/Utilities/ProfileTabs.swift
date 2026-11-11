import Foundation

/// Which of a person's tabs show — the web's `lib/profileTabs.ts`. A content tab shows once it has something in it.
enum ProfileTabs {
    struct Content {
        var isPregnancy = false
        var hasBirthday = true
        var quotes = 0
        var artwork = 0
        var interviews = 0
        var seasons = 0
    }

    static func tabs(_ content: Content) -> [PersonTab] {
        if content.isPregnancy { return [.story, .photos] }
        return PersonTab.allCases.filter { tab in
            switch tab {
            case .quotes: content.quotes > 0
            case .artwork: content.artwork > 0
            case .interviews: content.interviews > 0
            case .growth: content.hasBirthday
            case .activities: content.seasons > 0
            case .story, .photos: true
            }
        }
    }
}

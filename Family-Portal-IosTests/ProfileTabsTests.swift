import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/profileTabs.test.ts.
@MainActor
@Suite("Profile tabs")
struct ProfileTabsTests {

    @Test("Only Story, Photos and Growth when nothing else is recorded")
    func emptyPerson() {
        #expect(ProfileTabs.tabs(.init()) == [.story, .photos, .growth])
    }

    @Test("A tab appears once it has something in it")
    func filledPerson() {
        let tabs = ProfileTabs.tabs(.init(quotes: 2, artwork: 3, interviews: 1, seasons: 1))
        #expect(tabs == [.story, .quotes, .artwork, .interviews, .photos, .growth, .activities])
    }

    @Test("Growth needs a birthday")
    func noBirthday() {
        #expect(ProfileTabs.tabs(.init(hasBirthday: false)) == [.story, .photos])
    }

    @Test("A pregnancy keeps to Story and Photos")
    func pregnancy() {
        #expect(ProfileTabs.tabs(.init(isPregnancy: true, quotes: 1)) == [.story, .photos])
    }
}

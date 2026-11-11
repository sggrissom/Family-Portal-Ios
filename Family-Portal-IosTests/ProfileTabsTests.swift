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

    private let birthday = DaySummaryTests.date("2022-06-15T00:00:00Z")

    @Test("Editors are invited to interview from the third birthday")
    func invitesAtThree() {
        #expect(ProfileTabs.invitesInterview(birthday: birthday, isPregnancy: false, interviews: 0, editable: true, today: DaySummaryTests.date("2025-06-15T00:00:00Z")))
        #expect(!ProfileTabs.invitesInterview(birthday: birthday, isPregnancy: false, interviews: 0, editable: true, today: DaySummaryTests.date("2025-06-14T00:00:00Z")))
    }

    @Test("No invitation once there is an interview, for viewers, pregnancies, or without a birthday")
    func noInvitation() {
        let today = DaySummaryTests.date("2026-01-01T00:00:00Z")
        #expect(!ProfileTabs.invitesInterview(birthday: birthday, isPregnancy: false, interviews: 1, editable: true, today: today))
        #expect(!ProfileTabs.invitesInterview(birthday: birthday, isPregnancy: false, interviews: 0, editable: false, today: today))
        #expect(!ProfileTabs.invitesInterview(birthday: birthday, isPregnancy: true, interviews: 0, editable: true, today: today))
        #expect(!ProfileTabs.invitesInterview(birthday: nil, isPregnancy: false, interviews: 0, editable: true, today: today))
    }
}

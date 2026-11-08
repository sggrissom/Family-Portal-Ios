import Foundation
import SwiftUI
import Testing
@testable import Family_Portal_Ios

@Suite("App navigator")
@MainActor
struct AppNavigatorTests {

    @Test("An account-menu screen is handed back when its tab is left")
    func borrowedScreenReturnedOnLeave() {
        let navigator = AppNavigator()
        navigator.select(.explore)
        navigator.push(.settings)
        #expect(navigator.depth(of: .explore) == 1)

        navigator.select(.home)
        #expect(navigator.depth(of: .explore) == 0)
    }

    @Test("Only the borrowed part goes: the tab's own screens under it stay")
    func ownScreensKept() {
        let navigator = AppNavigator()
        navigator.select(.explore)
        navigator.push(.person(UUID()))
        navigator.push(.settings)
        // Something opened from Settings is part of what was borrowed.
        navigator.push(.person(UUID()))

        navigator.select(.home)
        #expect(navigator.depth(of: .explore) == 1)
    }

    @Test("A tab's own stack survives switching away and back")
    func ownStackKept() {
        let navigator = AppNavigator()
        navigator.push(.person(UUID()))
        navigator.push(.sameAge(ageMonths: 12, fromRemoteId: 3))

        navigator.select(.explore)
        navigator.select(.home)
        #expect(navigator.depth(of: .home) == 2)
    }

    @Test("Backing out of a borrowed screen by hand forgets it")
    func manualPopForgets() {
        let navigator = AppNavigator()
        navigator.push(.settings)
        navigator.path(for: .home).wrappedValue = NavigationPath()
        navigator.push(.person(UUID()))

        navigator.select(.explore)
        #expect(navigator.depth(of: .home) == 1)
    }

    @Test("A link to an account-menu screen is borrowed too")
    func linkShownIsBorrowed() {
        let navigator = AppNavigator()
        navigator.select(.explore)
        navigator.show([.settings])

        navigator.select(.home)
        #expect(navigator.depth(of: .explore) == 0)
    }

    @Test("Explore's destinations are its own: leaving the tab and coming back finds them")
    func moreKeepsItsStack() {
        let navigator = AppNavigator()
        navigator.show([.chat], on: .explore)
        #expect(navigator.selectedTab == .explore)

        navigator.select(.home)
        navigator.select(.explore)
        #expect(navigator.depth(of: .explore) == 1)
    }

    @Test("Explore's destinations are not borrowed; the account menu's screens are")
    func borrowedRoutes() {
        for route in [AppRoute.photos, .growth, .history, .chat, .activities, .books, .sameAge(ageMonths: nil, fromRemoteId: 0)] {
            #expect(!route.isBorrowed)
        }
        for route in [AppRoute.settings, .tags, .faces] {
            #expect(route.isBorrowed)
        }
    }

    @Test("A second tap on Explore goes back to its list")
    func moreReselect() {
        let navigator = AppNavigator()
        navigator.show([.history], on: .explore)
        navigator.popToRoot(.explore)
        #expect(navigator.depth(of: .explore) == 0)
    }

    @Test("Open in Photos shows the gallery on Explore with the filter")
    func openPhotosOnExplore() {
        let navigator = AppNavigator()
        let person = UUID()
        navigator.push(.person(person))
        navigator.openPhotos(of: person)

        #expect(navigator.selectedTab == .explore)
        #expect(navigator.depth(of: .explore) == 1)
        #expect(navigator.photoFilter.personLocalIds == [person])
        #expect(navigator.depth(of: .home) == 1)
    }
}

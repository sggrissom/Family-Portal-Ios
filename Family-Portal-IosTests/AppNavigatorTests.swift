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
        navigator.select(.growth)
        navigator.push(.settings)
        #expect(navigator.depth(of: .growth) == 1)

        navigator.select(.home)
        #expect(navigator.depth(of: .growth) == 0)
    }

    @Test("Only the borrowed part goes: the tab's own screens under it stay")
    func ownScreensKept() {
        let navigator = AppNavigator()
        navigator.select(.growth)
        navigator.push(.person(UUID()))
        navigator.push(.settings)
        // Something opened from Settings is part of what was borrowed.
        navigator.push(.person(UUID()))

        navigator.select(.home)
        #expect(navigator.depth(of: .growth) == 1)
    }

    @Test("A tab's own stack survives switching away and back")
    func ownStackKept() {
        let navigator = AppNavigator()
        navigator.push(.person(UUID()))
        navigator.push(.sameAge(ageMonths: 12, fromRemoteId: 3))

        navigator.select(.photos)
        navigator.select(.home)
        #expect(navigator.depth(of: .home) == 2)
    }

    @Test("Backing out of a borrowed screen by hand forgets it")
    func manualPopForgets() {
        let navigator = AppNavigator()
        navigator.push(.settings)
        navigator.path(for: .home).wrappedValue = NavigationPath()
        navigator.push(.person(UUID()))

        navigator.select(.photos)
        #expect(navigator.depth(of: .home) == 1)
    }

    @Test("A link to an account-menu screen is borrowed too")
    func linkShownIsBorrowed() {
        let navigator = AppNavigator()
        navigator.select(.growth)
        navigator.show([.settings])

        navigator.select(.home)
        #expect(navigator.depth(of: .growth) == 0)
    }

    @Test("More's destinations are its own: leaving the tab and coming back finds them")
    func moreKeepsItsStack() {
        let navigator = AppNavigator()
        navigator.show([.chat], on: .more)
        #expect(navigator.selectedTab == .more)

        navigator.select(.home)
        navigator.select(.more)
        #expect(navigator.depth(of: .more) == 1)
    }

    @Test("History, Chat, Activities and Books are not borrowed; the account menu's screens are")
    func borrowedRoutes() {
        for route in [AppRoute.history, .chat, .activities, .books, .sameAge(ageMonths: nil, fromRemoteId: 0)] {
            #expect(!route.isBorrowed)
        }
        for route in [AppRoute.settings, .tags, .faces] {
            #expect(route.isBorrowed)
        }
    }

    @Test("A second tap on More goes back to its list")
    func moreReselect() {
        let navigator = AppNavigator()
        navigator.show([.history], on: .more)
        navigator.popToRoot(.more)
        #expect(navigator.depth(of: .more) == 0)
    }
}


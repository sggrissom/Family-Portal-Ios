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
        navigator.push(.history)
        #expect(navigator.depth(of: .growth) == 1)

        navigator.select(.home)
        #expect(navigator.depth(of: .growth) == 0)
    }

    @Test("Only the borrowed part goes: the tab's own screens under it stay")
    func ownScreensKept() {
        let navigator = AppNavigator()
        navigator.select(.growth)
        navigator.push(.person(UUID()))
        navigator.push(.history)
        // Something opened from History is part of what was borrowed.
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
        navigator.push(.history)
        navigator.path(for: .home).wrappedValue = NavigationPath()
        navigator.push(.person(UUID()))

        navigator.select(.photos)
        #expect(navigator.depth(of: .home) == 1)
    }

    @Test("A link to an account-menu screen is borrowed too")
    func linkShownIsBorrowed() {
        let navigator = AppNavigator()
        navigator.select(.growth)
        navigator.show([.chat])

        navigator.select(.home)
        #expect(navigator.depth(of: .growth) == 0)
    }
}


//
//  Family_Portal_IosApp.swift
//  Family-Portal-Ios
//
//  Created by Grissom on 1/22/26.
//

import SwiftUI
import SwiftData

@main
struct Family_Portal_IosApp: App {
    let container: ModelContainer
    @State private var authService = AuthService()

    init() {
        container = DataStore.shared.container
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
        }
        .modelContainer(container)
    }
}

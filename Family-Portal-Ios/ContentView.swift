//
//  ContentView.swift
//  Family-Portal-Ios
//
//  Created by Grissom on 1/22/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        if authService.isAuthenticated {
            mainTabs
        } else if authService.hasCheckedStoredSession {
            LoginView()
        } else {
            launchPlaceholder
        }
    }

    private var launchPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            ProgressView()
        }
        .accessibilityLabel("Restoring your session")
    }

    private var mainTabs: some View {
        TabView {
            FamilyMembersView()
                .tabItem {
                    Label("Family", systemImage: "person.3")
                }

            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "clock.fill")
                }

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }

            PhotoGalleryView()
                .tabItem {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .modelContainer(for: Person.self, inMemory: true)
}

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
    @Environment(MobileVersionService.self) private var mobileVersionService
    @Environment(ChatService.self) private var chatService: ChatService?

    var body: some View {
        // The version gate sits outside the auth gate on purpose: the policy
        // endpoint is pre-auth so an unsupported build never reaches login.
        if mobileVersionService.status == .updateRequired {
            UpdateRequiredView(
                message: mobileVersionService.updateMessage,
                updateURL: mobileVersionService.updateURL
            )
        } else if authService.isAuthenticated {
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

            PhotoGalleryView()
                .tabItem {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .badge(chatService?.unreadCount ?? 0)
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(MobileVersionService())
        .modelContainer(for: Person.self, inMemory: true)
}

//
//  ContentView.swift
//  Family-Portal-Ios
//
//  Created by Grissom on 1/22/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
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
        .modelContainer(for: Person.self, inMemory: true)
}

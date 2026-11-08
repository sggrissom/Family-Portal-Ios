import SwiftUI

/// The Explore tab: the web's `/explore` directory as a native list, in the same fixed order. Each destination is pushed onto Explore's own stack, so it stays put when the user leaves the tab and comes back.
struct ExploreView: View {
    @Environment(ChatService.self) private var chatService: ChatService?

    var body: some View {
        List {
            Section {
                row(.photos, title: Copy.nav.photos, blurb: Copy.explore.photos, systemImage: "photo.on.rectangle")
                row(.history, title: Copy.nav.history, blurb: Copy.explore.history, systemImage: "calendar")
                row(.growth, title: Copy.nav.growth, blurb: Copy.explore.growth, systemImage: "chart.line.uptrend.xyaxis")
                row(.activities, title: Copy.nav.activities, blurb: Copy.explore.activities, systemImage: "trophy")
                row(.interviews, title: Copy.nav.interviews, blurb: Copy.explore.interviews, systemImage: "mic")
                row(.books, title: Copy.nav.books, blurb: Copy.explore.books, systemImage: "book.closed")
                // A direct visit: the server starts at the richest comparison.
                row(.sameAge(ageMonths: nil, fromRemoteId: 0), title: Copy.nav.sameAge, blurb: Copy.explore.sameAge, systemImage: "person.2")
                row(.chat, title: Copy.nav.chat, blurb: Copy.explore.chat, systemImage: "bubble.left.and.bubble.right")
                    .badge(chatService?.unreadCount ?? 0)
            }
        }
        .navigationTitle(Copy.explore.title)
    }

    private func row(_ route: AppRoute, title: String, blurb: String, systemImage: String) -> some View {
        NavigationLink(value: route) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

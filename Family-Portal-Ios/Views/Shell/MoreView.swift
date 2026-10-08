import SwiftUI

/// The More tab: the web's More sheet as a native list — History, Books, Same age, Activities and Chat, each with what it is for. They are pushed onto More's own stack, so they stay put when the user leaves the tab and comes back.
struct MoreView: View {
    @Environment(ChatService.self) private var chatService: ChatService?

    var body: some View {
        List {
            row(.history, title: Copy.nav.history, blurb: Copy.more.history, systemImage: "clock")
            row(.books, title: Copy.nav.books, blurb: Copy.more.books, systemImage: "book.closed")
            // A direct visit: the server starts at the richest comparison.
            row(.sameAge(ageMonths: nil, fromRemoteId: 0), title: Copy.nav.sameAge, blurb: Copy.more.sameAge, systemImage: "person.2")
            row(.activities, title: Copy.nav.activities, blurb: Copy.more.activities, systemImage: "trophy")
            row(.chat, title: Copy.nav.chat, blurb: Copy.more.chat, systemImage: "bubble.left.and.bubble.right")
                .badge(chatService?.unreadCount ?? 0)
        }
        .navigationTitle(Copy.nav.more)
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

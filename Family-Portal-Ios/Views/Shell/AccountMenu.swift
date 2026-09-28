import SwiftUI

/// The account button on every tab root: the user's initial, badged with unread chat so a new message is visible from anywhere. Its menu is the web's account menu without Import/Export and Admin — History, Chat and Activities are pushed onto the current tab; Tags and Face review are web-only and open the site.
struct AccountMenuButton: View {
    @Environment(AuthService.self) private var authService
    @Environment(ChatService.self) private var chatService: ChatService?
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.openURL) private var openURL

    @State private var isConfirmingLogOut = false

    private var unreadCount: Int { chatService?.unreadCount ?? 0 }

    private var initial: String {
        let name = authService.currentUser?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Menu {
            if let user = authService.currentUser {
                Section("\(Copy.account.signedInAs) \(user.name)") {}
            }

            Button {
                navigator.push(.history)
            } label: {
                Label(Copy.nav.history, systemImage: "clock")
            }
            Button {
                navigator.push(.chat)
            } label: {
                Label(unreadCount > 0 ? "\(Copy.nav.chat) (\(unreadCount))" : Copy.nav.chat, systemImage: "bubble.left.and.bubble.right")
            }
            Button {
                navigator.push(.activities)
            } label: {
                Label(Copy.account.activities, systemImage: "trophy")
            }

            Section {
                Button {
                    openWeb("/manage-tags")
                } label: {
                    Label(Copy.account.tags, systemImage: "tag")
                }
                if let faces = navigator.faceReviewCount {
                    Button {
                        openWeb("/faces")
                    } label: {
                        Label(faces > 0 ? "\(Copy.account.faceReview) (\(faces))" : Copy.account.faceReview, systemImage: "person.crop.square")
                    }
                }
            }

            Section {
                Button {
                    navigator.push(.settings)
                } label: {
                    Label(Copy.account.settings, systemImage: "gear")
                }
                Button(role: .destructive) {
                    isConfirmingLogOut = true
                } label: {
                    Label(Copy.account.logOut, systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            avatar
        }
        .accessibilityLabel(unreadCount > 0 ? "\(Copy.nav.account), \(unreadCount) unread messages" : Copy.nav.account)
        .confirmationDialog(Copy.account.logOut, isPresented: $isConfirmingLogOut) {
            Button(Copy.account.logOut, role: .destructive) {
                Task { await authService.logout() }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private var avatar: some View {
        Text(initial)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Color.accentColor, in: Circle())
            .overlay(alignment: .topTrailing) {
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(.red, in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
    }

    /// Tags and Face review have no native screen. Neither path is claimed by the universal-link association, so they open in the browser rather than bouncing back here.
    private func openWeb(_ path: String) {
        guard let url = URL(string: AppConstants.defaultServerURL + path) else { return }
        openURL(url)
    }
}

/// A tab's root: its own navigation stack, every app route registered once, and the account button in the corner.
struct TabRoot<Content: View>: View {
    let tab: MainTab
    @ViewBuilder let content: () -> Content

    @Environment(AppNavigator.self) private var navigator
    @Environment(AddFlow.self) private var addFlow

    var body: some View {
        NavigationStack(path: navigator.path(for: tab)) {
            content()
                .appDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountMenuButton()
                    }
                }
        }
        // Photos keep reading and queueing after the add flow closes; the bar shows that on whichever tab is up.
        .safeAreaInset(edge: .bottom) {
            if let progress = addFlow.importer.progress {
                PhotoImportProgressBar(progress: progress)
            }
        }
    }
}

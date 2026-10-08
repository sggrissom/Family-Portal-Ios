import SwiftUI

/// The account button on every tab root: the user's initial. Its menu is the web's account menu without Import/Export and Admin — Tags, Face review, Settings and Log out, each a native screen pushed onto the current tab. Browsing (History, Books, Same age, Activities, Chat) lives on the More tab, which carries the unread-chat badge.
/// Deliberately web-only, with no entry here: naming and managing family places, and the age-in-text parser on the milestone form. Places live on the web's `/settings`, a universal-link path, so a link from the app would only open the app again.
struct AccountMenuButton: View {
    @Environment(AuthService.self) private var authService
    @Environment(AppNavigator.self) private var navigator

    @State private var isConfirmingLogOut = false

    private var initial: String {
        let name = authService.currentUser?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Menu {
            if let user = authService.currentUser {
                Section("\(Copy.account.signedInAs) \(user.name)") {}
            }

            Section {
                // Managing tags is all the screen is for, so a view-only member — who can change none of them — is not sent there.
                if authService.access.canContributeAnywhere {
                    Button {
                        navigator.push(.tags)
                    } label: {
                        Label(Copy.account.tags, systemImage: "tag")
                    }
                }
                if let faces = navigator.faceReviewCount {
                    Button {
                        navigator.push(.faces)
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
        .accessibilityLabel(Copy.nav.account)
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

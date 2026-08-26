import SwiftUI

/// Account deletion, which App Store Review Guideline 5.1.1(v) requires of any
/// app that offers account creation — `CreateAccountView` does, so this screen
/// is not optional.
///
/// It wraps `POST /api/delete-account` (backend/account_deletion.go). What goes
/// and what stays is the backend's decision and this screen only reports it: the
/// sign-in, the sessions, the registered devices and the user's own chat
/// messages go; the family's records stay with the family as long as somebody
/// else is still in it; a family the deletion empties is destroyed with
/// everything in it. Getting that wording right matters more here than anywhere
/// else in the app, because it is the last thing the user reads before the only
/// irreversible action they can take.
struct DeleteAccountView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmEmail = ""
    @State private var errorMessage: String?
    @State private var showFinalConfirmation = false
    @State private var isDeleting = false

    /// The address the typed one has to match. The server compares
    /// case-insensitively after trimming, and so does `canSubmit` below, so the
    /// button is never enabled on something the server would then refuse.
    private var accountEmail: String {
        authService.currentUser?.email ?? ""
    }

    private var canSubmit: Bool {
        !isDeleting && confirmEmail.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(accountEmail.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text("Deleting your account removes your sign-in, your sessions, your registered devices and your chat messages.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Records stay with any family that still has another member in it. A family you are the only member of is deleted along with everything in it — people, photos, measurements and milestones.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Link(destination: AppConstants.privacyPolicyURL) {
                    Label("What goes and what stays", systemImage: "hand.raised")
                }
            }

            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } footer: {
                // A Google-only account has no password on file and the server
                // skips the check, so an empty field is a real answer here
                // rather than an incomplete form.
                Text("Leave blank if you sign in with Google.")
            }

            Section {
                TextField("Email address", text: $confirmEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Confirm your email address")
            } header: {
                Text("Type your email to confirm")
            } footer: {
                // In the footer rather than as the field's placeholder: a
                // placeholder disappears on the first keystroke, which is
                // exactly when the address needs to still be readable.
                Text(accountEmail)
                    .font(.callout.monospaced())
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                Button(role: .destructive) {
                    showFinalConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete My Account")
                                .bold()
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        // A push, so there is no interactive dismissal to disable — but the
        // back button is a way to leave mid-request, and the unstructured task
        // below would go on deleting the account behind an empty stack.
        .navigationBarBackButtonHidden(isDeleting)
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete My Account", role: .destructive) {
                Task { await submit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Any family you are the only member of is deleted with everything in it — people, photos, measurements and milestones.")
        }
    }

    private func submit() async {
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }

        let failure = await authService.deleteAccount(
            password: password,
            confirmEmail: confirmEmail.trimmingCharacters(in: .whitespaces)
        )

        guard let failure else {
            // The account is gone and the local store with it. Popping is
            // mostly belt and braces — `ContentView` gates on
            // `isAuthenticated`, so the whole tab has already been replaced by
            // the sign-in screen — but it leaves nothing standing on a stack
            // rooted in an account that no longer exists.
            dismiss()
            return
        }

        // A refusal leaves the session untouched, so the user stays here and
        // fixes the field the message names. The password is cleared because
        // the most likely refusal is a wrong one.
        password = ""
        errorMessage = failure
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView()
            .environment(AuthService())
    }
}

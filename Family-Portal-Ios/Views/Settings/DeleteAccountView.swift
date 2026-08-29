import SwiftUI

/// Account deletion, required by App Store Review Guideline 5.1.1(v). Wraps `POST /api/delete-account` (backend/account_deletion.go) and only reports what the backend decides goes and stays.
struct DeleteAccountView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmEmail = ""
    @State private var errorMessage: String?
    @State private var showFinalConfirmation = false
    @State private var isDeleting = false

    /// The address the typed one has to match. The server compares case-insensitively after trimming, and so does `canSubmit`.
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
                // A Google- or Apple-only account has no password on file and the server skips the check, so an empty field is a real answer here.
                Text("Leave blank if you sign in with Google or Apple.")
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
        // A push, so there is no interactive dismissal to disable — but the back button would leave the unstructured task below still deleting the account.
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
            dismiss()
            return
        }

        // A refusal leaves the session untouched. The password is cleared because the most likely refusal is a wrong one.
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

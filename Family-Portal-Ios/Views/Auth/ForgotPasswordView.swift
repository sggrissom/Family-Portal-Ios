import SwiftUI

/// Requests the reset email `RequestPasswordReset` (backend/password_reset.go) sends; the new password is chosen on the website.
struct ForgotPasswordView: View {
    @Environment(AuthService.self) private var authService

    @State private var email = ""
    @State private var errorMessage: String?
    @State private var didSend = false
    @State private var isSubmitting = false

    var body: some View {
        Form {
            if didSend {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Check your email", systemImage: "envelope.badge")
                            .font(.headline)
                        // The server answers identically for unknown addresses, so this must not imply the account exists.
                        Text("If an account exists for \(email), a password reset link is on its way. Open the link to choose a new password, then sign in here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Send Again") {
                        didSend = false
                    }
                }
            } else {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("We'll email you a link to reset your password.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Send Reset Link")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if let failure = await authService.requestPasswordReset(email: trimmed) {
            errorMessage = failure
        } else {
            email = trimmed
            didSend = true
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
            .environment(AuthService())
    }
}

import SwiftUI

/// Requests a reset email via `RequestPasswordReset` (backend/password_reset.go).
///
/// The reset itself is completed on the website: the server emails a link to
/// `<siteRoot>/reset-password?token=...`, which opens in a browser. Catching
/// that link in the app would need universal-link support, which requires an
/// apple-app-site-association file served from the site.
struct ForgotPasswordView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var didSend = false

    var body: some View {
        Form {
            if didSend {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                        Text("Check your email")
                            .font(.headline)
                        Text("If an account exists for that address, we've sent a link to reset your password. Opening it will take you to \(AppConstants.appName) in your browser.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button("Done") { dismiss() }
                }
            } else {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("We'll email you a link to choose a new password.")
                }

                if let error = authService.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { didSend = await authService.requestPasswordReset(email: email) }
                    } label: {
                        HStack {
                            Spacer()
                            if authService.isLoading {
                                ProgressView()
                            } else {
                                Text("Send Reset Link").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authService.isLoading)
                }
            }
        }
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { authService.clearError() }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
    }
    .environment(AuthService())
}

import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(AppConstants.appName)
                            .font(.title2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }

                Section {
                    SocialSignInButtons()
                }

                Section("Or with email") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
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
                        Task {
                            await authService.login(email: email, password: password)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if authService.isLoading && !authService.isGoogleSigningIn && !authService.isAppleSigningIn {
                                ProgressView()
                            } else {
                                Text("Sign In")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || authService.isLoading)
                }

                Section {
                    NavigationLink("Create Account") {
                        CreateAccountView()
                    }

                    NavigationLink("Forgot Password?") {
                        ForgotPasswordView()
                    }
                }
            }
            .navigationTitle("Sign In")
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    dismiss()
                }
            }
        }
    }
}

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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

                Section("Credentials") {
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
                    Button {
                        Task {
                            await authService.loginWithGoogle()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if authService.isGoogleSigningIn {
                                ProgressView()
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.title2)
                                    Text("Sign in with Google")
                                        .bold()
                                }
                            }
                            Spacer()
                        }
                    }
                    .disabled(authService.isLoading)

                    // Apple's own button rather than a lookalike: App Review checks that the
                    // system-drawn one is what a Sign in with Apple app presents.
                    SignInWithAppleButton(.signIn) { request in
                        authService.configureAppleRequest(request)
                    } onCompletion: { result in
                        Task { await authService.loginWithApple(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                    .disabled(authService.isLoading)
                    .accessibilityLabel("Sign in with Apple")
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

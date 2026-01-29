import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService
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
                            if authService.isLoading && !authService.isGoogleSigningIn {
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
                }

            }
            .navigationTitle("Sign In")
        }
    }
}

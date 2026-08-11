import SwiftUI

/// Mirrors the website's `auth/create-account.tsx` against the same
/// `CreateAccount` proc.
struct CreateAccountView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var familyCode = ""
    @State private var hasInviteCode = false

    /// The backend's own minimum; matched here so the failure is immediate
    /// rather than a round trip.
    private static let minimumPasswordLength = 8

    private var passwordsMatch: Bool {
        confirmPassword.isEmpty || password == confirmPassword
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= Self.minimumPasswordLength
            && password == confirmPassword
            && !authService.isLoading
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("About You")
            }

            Section {
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } header: {
                Text("Password")
            } footer: {
                if !passwordsMatch {
                    Text("Passwords don't match.")
                        .foregroundStyle(.red)
                } else {
                    Text("At least \(Self.minimumPasswordLength) characters.")
                }
            }

            Section {
                Toggle("I have an invite code", isOn: $hasInviteCode.animation())

                if hasInviteCode {
                    TextField("Invite code", text: $familyCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
            } footer: {
                Text(hasInviteCode
                     ? "You'll join the family that code belongs to."
                     : "We'll create a new family for you. You can invite others later from Settings.")
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
                        await authService.createAccount(
                            name: name,
                            email: email,
                            password: password,
                            confirmPassword: confirmPassword,
                            familyCode: hasInviteCode ? familyCode : ""
                        )
                    }
                } label: {
                    HStack {
                        Spacer()
                        if authService.isLoading {
                            ProgressView()
                        } else {
                            Text("Create Account").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { authService.clearError() }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            // The root view swaps to the tabs on its own; dismissing keeps this
            // screen from lingering if it was pushed from a presented Login.
            if isAuthenticated { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
    .environment(AuthService())
}

import SwiftUI

/// Sign-up, backed by `CreateAccount` in backend/users.go. Without it a new user
/// has no way onto the app at all — the website was previously the only place to
/// create an account.
struct CreateAccountView: View {
    @Environment(AuthService.self) private var authService

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var familyCode = ""
    @State private var addSelfToFamily = false
    @State private var birthdate = Date()
    @State private var gender: Gender = .other
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    /// Mirrors `validateCreateAccountRequest`, so the obvious mistakes are
    /// caught before a round trip.
    private var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Name is required"
        }
        if email.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Email is required"
        }
        if password.count < 8 {
            return "Password must be at least 8 characters"
        }
        if password != confirmPassword {
            return "Passwords do not match"
        }
        return nil
    }

    var body: some View {
        Form {
            Section("Your Account") {
                TextField("Name", text: $name)
                    .textContentType(.name)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
            }

            Section {
                TextField("Invite Code (optional)", text: $familyCode)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            } header: {
                Text("Family")
            } footer: {
                Text("Leave this blank to start a new family. Enter an invite code to join one that already exists.")
            }

            Section {
                Toggle("Add myself as a family member", isOn: $addSelfToFamily.animation())

                if addSelfToFamily {
                    DatePicker(
                        "Birthday",
                        selection: $birthdate,
                        in: ...Date(),
                        displayedComponents: .date
                    )

                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized).tag(option)
                        }
                    }
                }
            } footer: {
                Text("You can always add more family members later.")
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
                            Text("Create Account")
                                .bold()
                        }
                        Spacer()
                    }
                }
                .disabled(validationMessage != nil || isSubmitting)
            }
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        if let validationMessage {
            errorMessage = validationMessage
            return
        }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        errorMessage = await authService.createAccount(
            name: trimmedName,
            email: email.trimmingCharacters(in: .whitespaces),
            password: password,
            confirmPassword: confirmPassword,
            familyCode: familyCode.trimmingCharacters(in: .whitespaces),
            initialPerson: addSelfToFamily
                ? InitialPerson(name: trimmedName, gender: gender, birthdate: birthdate)
                : nil
        )
        // On success the root view swaps to the signed-in tabs, so there is
        // nothing to dismiss here.
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
            .environment(AuthService())
    }
}

import SwiftUI

/// Sign-up, backed by `CreateAccount` in backend/users.go.
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
    /// Adults the invited family already has without an account; picking one signs up as them.
    @State private var claims: [InviteClaimDTO] = []
    @State private var claimPersonId = 0
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    /// Mirrors `validateCreateAccountRequest`, so the obvious mistakes are caught before a round trip.
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

    private var trimmedFamilyCode: String {
        familyCode.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section {
                TextField("Invite Code (optional)", text: $familyCode)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            } header: {
                Text("Family")
            } footer: {
                Text("Leave this blank to start a new family. Enter an invite code to join one that already exists.")
            }

            if !claims.isEmpty {
                Section {
                    Picker("Are you already in this family?", selection: $claimPersonId) {
                        ForEach(claims) { claim in
                            Text(claim.name).tag(claim.personId)
                        }
                        Text("No, add me as someone new").tag(0)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Are you already in this family?")
                } footer: {
                    Text("If someone added you before inviting you, pick yourself so your account joins that profile instead of making a second one.")
                }
            }

            Section {
                SocialSignInButtons(familyCode: trimmedFamilyCode)
            }

            if let socialError = authService.errorMessage {
                Section {
                    Text(socialError)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("Or sign up with email") {
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

            if claimPersonId == 0 {
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
                                Text(option.label).tag(option)
                            }
                        }
                    }
                } footer: {
                    Text("You can always add more family members later.")
                }
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
        .onAppear { authService.clearError() }
        // Looked up once the code stops changing; a newer code cancels the older lookup.
        .task(id: trimmedFamilyCode) {
            claimPersonId = 0
            claims = []
            guard !trimmedFamilyCode.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let found = await authService.inviteClaims(code: trimmedFamilyCode)
            if !Task.isCancelled { claims = found }
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
            familyCode: trimmedFamilyCode,
            initialPerson: addSelfToFamily && claimPersonId == 0
                ? InitialPerson(name: trimmedName, gender: gender, birthdate: birthdate)
                : nil,
            claimPersonId: claimPersonId
        )
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
            .environment(AuthService())
    }
}

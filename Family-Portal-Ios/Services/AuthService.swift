import AuthenticationServices
import Foundation
import OSLog

@Observable
final class AuthService {
    private(set) var currentUser: AuthResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var hasCheckedStoredSession = false

    private let googleSignInService = GoogleSignInService()
    private let appleSignInService = AppleSignInService()

    @MainActor var onWillLogout: (@MainActor () async -> Void)?

    /// Runs when the data on this device cannot be vouched for as the signing-in account's, before the new identity is published — see `LocalAccountOwner`.
    @MainActor var onUnownedLocalData: (@MainActor (LocalDataResetScope) async -> Void)?

    /// Runs after the server has destroyed the account. Nothing remains to reconcile against, so the store is erased outright.
    @MainActor var onAccountDeleted: (@MainActor () async -> Void)?

    private let accountOwner = LocalAccountOwner()

    var isAuthenticated: Bool {
        currentUser != nil
    }

    var isGoogleSigningIn: Bool {
        googleSignInService.isSigningIn
    }

    /// Apple's button owns its own presentation, so this covers only the token exchange that follows it.
    @MainActor private(set) var isAppleSigningIn = false

    init() {}

    @MainActor
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            struct LoginRequest: Encodable {
                let email: String
                let password: String
            }

            let response: LoginResponseDTO = try await APIClient.shared.request(
                path: "api/login",
                method: .post,
                body: LoginRequest(email: email, password: password),
                requiresAuth: false
            )

            if response.success, let token = response.token, let auth = response.auth {
                await APIClient.shared.setAccessToken(token)
                await adoptSession(auth)
            } else {
                errorMessage = response.error ?? "Login failed."
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    func createAccount(
        name: String,
        email: String,
        password: String,
        confirmPassword: String,
        familyCode: String = "",
        initialPerson: InitialPerson? = nil
    ) async -> String? {
        isLoading = true
        defer { isLoading = false }

        let personName = initialPerson.map { $0.name.isEmpty ? name : $0.name } ?? name

        let request = CreateAccountRequestDTO(
            name: name,
            email: email,
            password: password,
            confirmPassword: confirmPassword,
            familyCode: familyCode,
            initialPersonName: personName,
            initialPersonGender: genderToInt(initialPerson?.gender ?? .other),
            initialPersonBirthdate: initialPerson.map { dateToAPIString($0.birthdate) } ?? ""
        )

        do {
            let response: CreateAccountResponseDTO = try await APIClient.shared.callPublicRPC(
                .createAccount,
                payload: request
            )

            guard response.success, let token = response.token, let auth = response.auth else {
                return response.error ?? "Could not create your account."
            }

            await APIClient.shared.setAccessToken(token)
            errorMessage = nil
            await adoptSession(auth)
            return nil
        } catch let error as APIError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    @MainActor
    func requestPasswordReset(email: String) async -> String? {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: RequestPasswordResetResponseDTO = try await APIClient.shared.callPublicRPC(
                .requestPasswordReset,
                payload: RequestPasswordResetRequestDTO(email: email)
            )

            guard response.success else {
                return response.error ?? "Could not send the reset email."
            }
            return nil
        } catch let error as APIError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    @MainActor
    func loginWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            let idToken = try await googleSignInService.signIn()

            let response: LoginResponseDTO = try await APIClient.shared.request(
                path: "api/login/google/token",
                method: .post,
                body: GoogleTokenLoginRequestDTO(idToken: idToken),
                requiresAuth: false
            )

            if response.success, let token = response.token, let auth = response.auth {
                await APIClient.shared.setAccessToken(token)
                await adoptSession(auth)
            } else {
                errorMessage = response.error ?? "Google sign-in failed."
            }
        } catch let error as GoogleSignInError {
            if case .cancelled = error {
            } else {
                errorMessage = error.errorDescription
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        appleSignInService.configure(request)
    }

    /// Takes the button's raw result so cancellation — which Apple reports as a failure — is
    /// classified in one place rather than in the view.
    @MainActor
    func loginWithApple(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        isAppleSigningIn = true
        errorMessage = nil
        defer {
            isAppleSigningIn = false
            isLoading = false
        }

        do {
            let credential = try appleSignInService.credential(from: result)

            let response: LoginResponseDTO = try await APIClient.shared.request(
                path: "api/login/apple/token",
                method: .post,
                body: AppleTokenLoginRequestDTO(idToken: credential.identityToken, name: credential.name),
                requiresAuth: false
            )

            if response.success, let token = response.token, let auth = response.auth {
                await APIClient.shared.setAccessToken(token)
                await adoptSession(auth)
            } else {
                errorMessage = response.error ?? "Apple sign-in failed."
            }
        } catch let error as AppleSignInError {
            if case .cancelled = error {
            } else {
                errorMessage = error.errorDescription
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Families

    @MainActor private(set) var families: [FamilyInfoDTO] = []

    @MainActor
    func loadFamilyInfo() async -> String? {
        do {
            struct EmptyPayload: Encodable {}
            let response: FamilyInfoResponseDTO = try await APIClient.shared.callRPC(
                .getFamilyInfo,
                payload: EmptyPayload()
            )
            families = response.families
            return nil
        } catch let error as APIError {
            families = []
            return error.errorDescription
        } catch {
            families = []
            return error.localizedDescription
        }
    }

    @MainActor
    func joinFamily(inviteCode: String) async -> String? {
        do {
            let response: JoinFamilyResponseDTO = try await APIClient.shared.callRPC(
                .joinFamily,
                payload: JoinFamilyRequestDTO(inviteCode: inviteCode)
            )

            guard response.success else {
                return response.error ?? "Could not join that family."
            }

            if let auth = response.auth {
                setCurrentUser(auth)
            }
            return await loadFamilyInfo()
        } catch let error as APIError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    @MainActor
    func applyLeftFamily(_ familyId: Int, auth: AuthResponseDTO?) async {
        if let auth {
            setCurrentUser(auth)
        }

        let remaining = families.filter { $0.id != familyId }
        families = remaining

        if await loadFamilyInfo() != nil {
            families = remaining
        }
    }

    @MainActor
    func applyRotatedInviteCode(_ inviteCode: String, forFamily familyId: Int) {
        guard let index = families.firstIndex(where: { $0.id == familyId }) else { return }
        families[index] = families[index].withInviteCode(inviteCode)
    }

    @MainActor
    func logout() async {
        await onWillLogout?()

        do {
            struct EmptyBody: Encodable {}
            let _: LogoutResponseDTO = try await APIClient.shared.request(
                path: "api/logout",
                method: .post,
                body: EmptyBody?.none,
                requiresAuth: true,
                retryOnAuthFailure: false
            )
        } catch {
        }

        googleSignInService.signOut()

        await endSession()
    }

    /// Unlike `logout`, nothing local happens until the server has confirmed: a refused deletion must leave the user signed in with their data intact.
    /// `onWillLogout` is deliberately not called — `deleteAccountTx` already drops every push token the user has, on every device.
    @MainActor
    func deleteAccount(password: String, confirmEmail: String) async -> String? {
        isLoading = true
        defer { isLoading = false }

        do {
            try await APIClient.shared.deleteAccount(password: password, confirmEmail: confirmEmail)
        } catch {
            AppLog.auth.error("Account deletion failed: \(String(describing: error), privacy: .public)")
            return error.localizedDescription
        }

        // Google's own session outlives ours, so a Google user who did not sign out of it would be signed straight back in by the next tap.
        googleSignInService.signOut()

        await onAccountDeleted?()
        await endSession()
        return nil
    }

    @MainActor
    func restoreSession() async {
        defer { hasCheckedStoredSession = true }

        let onSessionExpired: @MainActor () async -> Void = { [weak self] in
            guard let self else { return }
            self.endSessionLocally()
        }
        await APIClient.shared.setSessionExpiredHandler(onSessionExpired)

        guard await APIClient.shared.hasRefreshCredential else {
            endSessionLocally()
            return
        }

        do {
            struct EmptyBody: Encodable {}
            let response: RefreshResponseDTO = try await APIClient.shared.request(
                path: "api/refresh",
                method: .post,
                body: EmptyBody?.none,
                requiresAuth: false,
                retryOnAuthFailure: false
            )
            if response.success, let token = response.token {
                await APIClient.shared.setAccessToken(token)
                await adoptSession(response.auth ?? Self.cachedUser())
            } else {
                await endSession()
            }
        } catch APIError.unauthorized {
            await endSession()
        } catch {
            // A network failure says nothing about whether the session is good: keep the tokens, and let the 401 handling catch a genuinely dead one.
            await adoptSession(Self.cachedUser())
        }
    }

    /// The erase is awaited before `currentUser` is set, so the app can never render a tab against the previous account's records.
    /// A sign-out deliberately leaves the recorded owner alone: the same user signing back in keeps everything they had.
    @MainActor
    private func adoptSession(_ auth: AuthResponseDTO?) async {
        guard let auth else {
            setCurrentUser(nil)
            return
        }

        if accountOwner.holdsDataForAnotherAccount(than: auth.id) {
            await onUnownedLocalData?(.everything)
        } else if !accountOwner.hasRecordedOwner {
            await onUnownedLocalData?(.chatOnly)
        }
        accountOwner.record(userId: auth.id)
        setCurrentUser(auth)
    }

    @MainActor
    private func endSessionLocally() {
        setCurrentUser(nil)
        families = []
    }

    @MainActor
    private func endSession() async {
        await APIClient.shared.clearTokens()
        endSessionLocally()
    }

    // MARK: - Cached identity

    private static let cachedUserKey = "com.familyrecord.cachedAuthUser"

    @MainActor
    private func setCurrentUser(_ user: AuthResponseDTO?) {
        currentUser = user

        guard let user, let data = try? JSONEncoder().encode(user) else {
            UserDefaults.standard.removeObject(forKey: Self.cachedUserKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.cachedUserKey)
    }

    private static func cachedUser() -> AuthResponseDTO? {
        guard let data = UserDefaults.standard.data(forKey: cachedUserKey) else { return nil }
        return try? JSONDecoder().decode(AuthResponseDTO.self, from: data)
    }

    // MARK: - Google Sign-In URL Handling

    func handleGoogleSignInURL(_ url: URL) -> Bool {
        googleSignInService.handle(url)
    }
}

struct InitialPerson {
    var name: String
    var gender: Gender
    var birthdate: Date
}

// MARK: - Additional DTOs

nonisolated struct LogoutResponseDTO: Codable {
    let success: Bool
}

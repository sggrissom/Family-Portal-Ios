import AuthenticationServices
import Foundation
import OSLog

/// Main-actor isolated, like everything in this target without a `nonisolated` of its own (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
@Observable
final class AuthService {
    private(set) var currentUser: AuthResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var hasCheckedStoredSession = false

    private let googleSignInService = GoogleSignInService()
    private let appleSignInService = AppleSignInService()

    // These three keep their explicit `@MainActor`: without it, `@Observable`'s generated storage infers a different closure type and the accessors no longer compile.
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
    private(set) var isAppleSigningIn = false

    init() {}

    func login(email: String, password: String) async {
        struct LoginRequest: Encodable {
            let email: String
            let password: String
        }
        await signIn(fallback: "Login failed.") {
            try await APIClient.shared.request(
                path: "api/login",
                body: LoginRequest(email: email, password: password),
                requiresAuth: false
            )
        }
    }

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
            initialPersonBirthdate: initialPerson.map { WhenEntry.localDateString($0.birthdate) } ?? ""
        )

        do {
            let response: SessionResponseDTO = try await APIClient.shared.callPublicRPC(.createAccount, payload: request)
            try await adopt(response, fallback: "Could not create your account.")
            errorMessage = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func requestPasswordReset(email: String) async -> String? {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: RequestPasswordResetResponseDTO = try await APIClient.shared.callPublicRPC(
                .requestPasswordReset,
                payload: RequestPasswordResetRequestDTO(email: email)
            )
            _ = try response.accepted(or: "Could not send the reset email.")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func loginWithGoogle(familyCode: String = "") async {
        await signIn(fallback: "Google sign-in failed.") {
            let idToken = try await self.googleSignInService.signIn()
            return try await APIClient.shared.request(
                path: "api/login/google/token",
                body: GoogleTokenLoginRequestDTO(idToken: idToken, familyCode: familyCode),
                requiresAuth: false
            )
        }
    }

    /// Lets a screen that shows `errorMessage` start clean rather than showing another screen's failure.
    func clearError() {
        errorMessage = nil
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        appleSignInService.configure(request)
    }

    /// Takes the button's raw result so cancellation — which Apple reports as a failure — is
    /// classified in one place rather than in the view.
    func loginWithApple(_ result: Result<ASAuthorization, Error>, familyCode: String = "") async {
        isAppleSigningIn = true
        defer { isAppleSigningIn = false }

        await signIn(fallback: "Apple sign-in failed.") {
            let credential = try self.appleSignInService.credential(from: result)
            return try await APIClient.shared.request(
                path: "api/login/apple/token",
                body: AppleTokenLoginRequestDTO(
                    idToken: credential.identityToken,
                    name: credential.name,
                    authorizationCode: credential.authorizationCode,
                    familyCode: familyCode
                ),
                requiresAuth: false
            )
        }
    }

    /// Every sign-in ends the same way: a token and an identity to adopt, or a sentence for `errorMessage`. Backing out of Google's or Apple's own sheet is not an error worth showing.
    private func signIn(fallback: String, _ exchange: @MainActor () async throws -> SessionResponseDTO) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await adopt(exchange(), fallback: fallback)
        } catch GoogleSignInError.cancelled, AppleSignInError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps the token and adopts the identity a sign-in answered with, or throws the server's refusal.
    private func adopt(_ response: SessionResponseDTO, fallback: String) async throws {
        guard response.success, let token = response.token, let auth = response.auth else {
            throw ServerRefusal(message: response.error ?? fallback)
        }
        await APIClient.shared.setAccessToken(token)
        await adoptSession(auth)
    }

    // MARK: - Families

    private(set) var families: [FamilyInfoDTO] = []

    func loadFamilyInfo() async -> String? {
        do {
            let response: FamilyInfoResponseDTO = try await APIClient.shared.callRPC(.getFamilyInfo, payload: EmptyRequestDTO())
            families = response.families
            return nil
        } catch {
            families = []
            return error.localizedDescription
        }
    }

    func joinFamily(inviteCode: String) async -> String? {
        do {
            let response: FamilyChangeResponseDTO = try await APIClient.shared.callRPC(
                .joinFamily,
                payload: JoinFamilyRequestDTO(inviteCode: inviteCode)
            )
            if let auth = try response.accepted(or: "Could not join that family.").auth {
                setCurrentUser(auth)
            }
            return await loadFamilyInfo()
        } catch {
            return error.localizedDescription
        }
    }

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

    func applyRotatedInviteCode(_ inviteCode: String, forFamily familyId: Int) {
        guard let index = families.firstIndex(where: { $0.id == familyId }) else { return }
        families[index] = families[index].withInviteCode(inviteCode)
    }

    func logout() async {
        await onWillLogout?()

        let _: LogoutResponseDTO? = try? await APIClient.shared.request(
            path: "api/logout",
            body: EmptyRequestDTO?.none,
            retryOnAuthFailure: false
        )

        googleSignInService.signOut()

        await endSession()
    }

    /// Unlike `logout`, nothing local happens until the server has confirmed: a refused deletion must leave the user signed in with their data intact.
    /// `onWillLogout` is deliberately not called — `deleteAccountTx` already drops every push token the user has, on every device.
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

    /// Signs back in from what the device already holds, without touching the network: the family's data is local, so a launch on a weak or missing signal must not wait on a server round trip to show it. `revalidateSession()` then checks the session with the server.
    func restoreSession() async {
        let onSessionExpired: @MainActor () async -> Void = { [weak self] in
            guard let self else { return }
            self.endSessionLocally()
        }
        await APIClient.shared.setSessionExpiredHandler(onSessionExpired)

        guard await APIClient.shared.hasRefreshCredential else {
            endSessionLocally()
            hasCheckedStoredSession = true
            return
        }

        // With no cached identity there is nothing to show yet, so the launch placeholder stays up until `revalidateSession()` answers.
        if let cached = Self.cachedUser() {
            await adoptSession(cached)
            hasCheckedStoredSession = true
        }
    }

    /// Refreshes the restored session. Goes through the client's single-flight refresh, since a sync started by the restore may be refreshing at the same moment and the server rotates the refresh token on every use.
    /// Only the server refusing the credential ends the session — the client's expiry handler does that. A network failure keeps the cached identity, and the next request's 401 handling catches a genuinely dead session.
    func revalidateSession() async {
        defer { hasCheckedStoredSession = true }
        guard await APIClient.shared.hasRefreshCredential else { return }

        do {
            if let auth = try await APIClient.shared.refreshAccessToken() {
                await adoptSession(auth)
            }
        } catch {
            AppLog.auth.info("Session revalidation deferred: \(String(describing: error), privacy: .public)")
        }
    }

    /// The erase is awaited before `currentUser` is set, so the app can never render a tab against the previous account's records.
    /// A sign-out deliberately leaves the recorded owner alone: the same user signing back in keeps everything they had.
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

    private func endSessionLocally() {
        setCurrentUser(nil)
        families = []
    }

    private func endSession() async {
        await APIClient.shared.clearTokens()
        endSessionLocally()
    }

    // MARK: - Cached identity

    private static let cachedUserKey = "com.familyrecord.cachedAuthUser"

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

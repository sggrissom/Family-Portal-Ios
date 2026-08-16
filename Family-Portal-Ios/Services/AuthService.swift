import Foundation

@Observable
final class AuthService {
    private(set) var currentUser: AuthResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// False until `restoreSession()` has finished once. Lets the root view hold
    /// a launch placeholder instead of flashing the sign-in screen at a user who
    /// turns out to have a valid session.
    private(set) var hasCheckedStoredSession = false

    private let googleSignInService = GoogleSignInService()

    /// Runs at the start of `logout`, while the session is still valid. Push
    /// registration is retired here so it can't be missed by whichever screen
    /// happens to trigger the sign-out.
    @MainActor var onWillLogout: (@MainActor () async -> Void)?

    var isAuthenticated: Bool {
        currentUser != nil
    }

    var isGoogleSigningIn: Bool {
        googleSignInService.isSigningIn
    }

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
                setCurrentUser(auth)
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

    /// `CreateAccount` (backend/users.go) creates the account, its family, and
    /// an optional first person, then returns a token — so a successful sign-up
    /// leaves the user signed in exactly as `login` would.
    ///
    /// Returns nil on success or a message to show the user. The failure is kept
    /// out of the shared `errorMessage` so it can't surface on the sign-in
    /// screen behind this one.
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

        // The website falls back to the account name here, and the backend
        // validates the person only when a birthdate is present.
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
            setCurrentUser(auth)
            return nil
        } catch let error as APIError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    /// `RequestPasswordReset` (backend/password_reset.go) emails a link to the
    /// website's reset page. It answers identically for unknown addresses, so
    /// the caller must not claim the account exists.
    ///
    /// Returns nil on success or a message to show the user.
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
            // Get ID token from Google
            let idToken = try await googleSignInService.signIn()

            // Send token to backend for verification
            let response: LoginResponseDTO = try await APIClient.shared.request(
                path: "api/login/google/token",
                method: .post,
                body: GoogleTokenLoginRequestDTO(idToken: idToken),
                requiresAuth: false
            )

            if response.success, let token = response.token, let auth = response.auth {
                await APIClient.shared.setAccessToken(token)
                setCurrentUser(auth)
            } else {
                errorMessage = response.error ?? "Google sign-in failed."
            }
        } catch let error as GoogleSignInError {
            if case .cancelled = error {
                // User cancelled, don't show error
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

    // MARK: - Families

    /// `GetFamilyInfo` (backend/users.go). Every family the user belongs to,
    /// each with the invite code others need to join it. Empty until loaded.
    @MainActor private(set) var families: [FamilyInfoDTO] = []

    /// Returns nil on success or a message to show the user. A user with no
    /// family at all gets an error rather than an empty list, which is why the
    /// caller has to distinguish "not loaded" from "none".
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

    /// `JoinFamily` (backend/users.go). The joined family's people show up on
    /// the next pull, since `GetFamilyTimeline` reads every family the user can
    /// see — so callers should sync afterwards.
    ///
    /// Returns nil on success or a message to show the user.
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

    /// The user is no longer in this family (`FamilyMembershipService.leaveFamily`).
    /// Which family is primary may have moved with it, so the server's refreshed
    /// identity is adopted and the list re-read.
    ///
    /// The local list is trimmed *first* and put back if the re-read fails:
    /// `loadFamilyInfo` empties `families` on any error, which would turn a
    /// successful leave into "You aren't part of a family yet."
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

    /// Records a rotated invite code without a round trip: `RotateInviteCode`
    /// returns the new code, and it is the same value `GetFamilyInfo` would.
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
            // Logout locally even if server call fails
        }

        // Sign out of Google as well
        googleSignInService.signOut()

        await endSession()
    }

    @MainActor
    func restoreSession() async {
        defer { hasCheckedStoredSession = true }

        // Registered here because this is the first thing the app does with the
        // API, so no request can outrun it.
        let onSessionExpired: @MainActor () async -> Void = { [weak self] in
            guard let self else { return }
            self.endSessionLocally()
        }
        await APIClient.shared.setSessionExpiredHandler(onSessionExpired)

        guard await APIClient.shared.hasRefreshCredential else {
            // Nothing to refresh with: a fresh install, or a real sign-out.
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
                setCurrentUser(response.auth ?? Self.cachedUser())
            } else {
                await endSession()
            }
        } catch APIError.unauthorized {
            // The refresh token is expired, revoked, or was reused. This is the
            // only launch-time failure that should cost the user their session.
            await endSession()
        } catch {
            // No network on launch, a DNS hiccup, a 502 — none of which say
            // anything about whether the session is still good. Keep the tokens
            // and carry on with the identity from last time; the next request
            // refreshes for real, and a genuinely dead session gets caught by
            // the 401 handling there.
            setCurrentUser(Self.cachedUser())
        }
    }

    /// Forgets the session locally. The tokens are already gone by the time the
    /// API client calls this, so there is nothing to revoke server-side.
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

    /// The last known signed-in user, so a launch without connectivity can show
    /// the app instead of a sign-in screen the user cannot get past offline.
    /// Nothing here is a credential — the tokens live in the keychain.
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

/// The first family member to create alongside a new account, mirroring the
/// optional block on the website's create-account form.
struct InitialPerson {
    var name: String
    var gender: Gender
    var birthdate: Date
}

// MARK: - Additional DTOs

struct LogoutResponseDTO: Codable {
    let success: Bool
}

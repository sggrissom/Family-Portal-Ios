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
                await APIClient.shared.setTokens(accessToken: token, refreshToken: nil)
                currentUser = auth
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

    /// `CreateAccount` (backend/users.go). A blank `familyCode` is fine — the
    /// backend then creates "<Name>'s Family" and makes the user its admin.
    @MainActor
    func createAccount(
        name: String,
        email: String,
        password: String,
        confirmPassword: String,
        familyCode: String
    ) async {
        isLoading = true
        errorMessage = nil

        do {
            let trimmedCode = familyCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let response: CreateAccountResponseDTO = try await APIClient.shared.callRPCUnauthenticated(
                "CreateAccount",
                payload: CreateAccountRequestDTO(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    confirmPassword: confirmPassword,
                    familyCode: trimmedCode.isEmpty ? nil : trimmedCode
                )
            )

            if response.success, let token = response.token, let auth = response.auth {
                await APIClient.shared.setTokens(accessToken: token, refreshToken: nil)
                currentUser = auth
            } else {
                errorMessage = response.error ?? "Could not create your account."
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// `RequestPasswordReset` (backend/password_reset.go). The server emails a
    /// link to the website; there is no in-app completion step.
    ///
    /// Returns true when the request was accepted. The backend deliberately
    /// reports success for unknown addresses so this can't be used to discover
    /// which emails have accounts — so a true result means "we sent it if that
    /// address exists", not "that address exists".
    @MainActor
    func requestPasswordReset(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: RequestPasswordResetResponseDTO = try await APIClient.shared.callRPCUnauthenticated(
                "RequestPasswordReset",
                payload: RequestPasswordResetRequestDTO(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )

            if response.success {
                return true
            }
            errorMessage = response.error ?? "Could not send the reset email."
            return false
        } catch let error as APIError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `JoinFamily` (backend/users.go). Refreshes `currentUser` so the rest of
    /// the app sees the new membership.
    @MainActor
    func joinFamily(inviteCode: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.joinFamily(
                inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            if response.success {
                if let auth = response.auth {
                    currentUser = auth
                }
                return true
            }
            errorMessage = response.error ?? "Could not join that family."
            return false
        } catch let error as APIError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func clearError() {
        errorMessage = nil
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
                await APIClient.shared.setTokens(accessToken: token, refreshToken: nil)
                currentUser = auth
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

    @MainActor
    func logout() async {
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

        await APIClient.shared.clearTokens()
        currentUser = nil
    }

    @MainActor
    func restoreSession() async {
        defer { hasCheckedStoredSession = true }

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
                await APIClient.shared.setTokens(accessToken: token, refreshToken: nil)
                currentUser = response.auth
            } else {
                await APIClient.shared.clearTokens()
            }
        } catch {
            await APIClient.shared.clearTokens()
        }
    }

    // MARK: - Google Sign-In URL Handling

    func handleGoogleSignInURL(_ url: URL) -> Bool {
        googleSignInService.handle(url)
    }
}

// MARK: - Additional DTOs

struct LogoutResponseDTO: Codable {
    let success: Bool
}

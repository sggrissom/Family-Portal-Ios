import Foundation

@Observable
final class AuthService {
    private(set) var currentUser: AuthResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

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

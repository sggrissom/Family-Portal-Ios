import Foundation

@Observable
final class AuthService {
    private(set) var currentUser: AuthResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var serverURL: String = AppConstants.defaultServerURL

    var isAuthenticated: Bool {
        currentUser != nil
    }

    init() {
        if let saved = loadServerURL() {
            serverURL = saved
        }
    }

    @MainActor
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // Update server URL before login
            if let url = URL(string: serverURL) {
                await APIClient.shared.updateBaseURL(url)
            }

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

    func updateServerURL(_ urlString: String) {
        serverURL = urlString
        saveServerURL(urlString)
        if let url = URL(string: urlString) {
            Task {
                await APIClient.shared.updateBaseURL(url)
            }
        }
    }

    // MARK: - Server URL Persistence

    private func saveServerURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: "serverURL")
    }

    private func loadServerURL() -> String? {
        UserDefaults.standard.string(forKey: "serverURL")
    }
}

// MARK: - Additional DTOs

struct LogoutResponseDTO: Codable {
    let success: Bool
}

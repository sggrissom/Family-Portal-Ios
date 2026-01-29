import Foundation
import GoogleSignIn

enum GoogleSignInError: LocalizedError {
    case cancelled
    case noIDToken
    case networkError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in was cancelled"
        case .noIDToken:
            return "Could not get ID token from Google"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let error):
            return "Sign in failed: \(error.localizedDescription)"
        }
    }
}

@Observable
final class GoogleSignInService {
    private(set) var isSigningIn = false

    /// Signs in with Google and returns the ID token
    @MainActor
    func signIn() async throws -> String {
        isSigningIn = true
        defer { isSigningIn = false }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw GoogleSignInError.unknown(NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root view controller"]))
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw GoogleSignInError.noIDToken
            }

            return idToken
        } catch let error as GIDSignInError {
            switch error.code {
            case .canceled:
                throw GoogleSignInError.cancelled
            case .hasNoAuthInKeychain:
                throw GoogleSignInError.unknown(error)
            default:
                throw GoogleSignInError.unknown(error)
            }
        } catch let error as NSError {
            if error.domain == NSURLErrorDomain {
                throw GoogleSignInError.networkError(error)
            }
            throw GoogleSignInError.unknown(error)
        }
    }

    /// Signs out of Google
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// Handles the URL callback from Google Sign-In
    func handle(_ url: URL) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

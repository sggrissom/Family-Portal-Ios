import AuthenticationServices
import Foundation

enum AppleSignInError: LocalizedError {
    case cancelled
    case noIdentityToken
    case failed(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in was cancelled"
        case .noIdentityToken:
            return "Could not get an identity token from Apple"
        case .failed(let error):
            return "Sign in failed: \(error.localizedDescription)"
        }
    }
}

/// What `SignInWithAppleButton` hands back, reduced to the two things the backend reads.
struct AppleCredential: Sendable {
    let identityToken: String
    /// Apple releases the name only in the response to the very first authorization and never
    /// again, so this is empty for every returning user — `upsertAppleUser` falls back on its own.
    let name: String
}

/// Apple's own button owns the presentation, so unlike `GoogleSignInService` there is nothing to
/// drive here: this configures the request and reads the result the button reports.
struct AppleSignInService: Sendable {

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        // `email` is what the account is matched on; the backend refuses a token without one.
        request.requestedScopes = [.fullName, .email]
    }

    func credential(from result: Result<ASAuthorization, Error>) throws -> AppleCredential {
        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleCredential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  !identityToken.isEmpty else {
                throw AppleSignInError.noIdentityToken
            }
            return AppleCredential(
                identityToken: identityToken,
                name: Self.displayName(from: appleCredential.fullName)
            )
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                throw AppleSignInError.cancelled
            }
            throw AppleSignInError.failed(error)
        }
    }

    /// The backend takes a single string and trims it, so an empty result means "nothing to say"
    /// rather than a name made of stray spaces.
    static func displayName(from components: PersonNameComponents?) -> String {
        guard let components else { return "" }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

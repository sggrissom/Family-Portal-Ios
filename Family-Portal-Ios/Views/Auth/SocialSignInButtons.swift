import AuthenticationServices
import SwiftUI

/// Google and Apple sign-in. Either one creates the account on first use, so sign-in and sign-up share these.
struct SocialSignInButtons: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme

    /// An invite code to join with. Empty signs in, or starts a new family, as usual.
    var familyCode: String = ""

    var body: some View {
        Button {
            Task {
                await authService.loginWithGoogle(familyCode: familyCode)
            }
        } label: {
            HStack {
                Spacer()
                if authService.isGoogleSigningIn {
                    ProgressView()
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "g.circle.fill")
                            .font(.title2)
                        Text("Sign in with Google")
                            .bold()
                    }
                }
                Spacer()
            }
        }
        .disabled(authService.isLoading)

        // Apple's own button rather than a lookalike: App Review checks that the
        // system-drawn one is what a Sign in with Apple app presents.
        SignInWithAppleButton(.signIn) { request in
            authService.configureAppleRequest(request)
        } onCompletion: { result in
            Task { await authService.loginWithApple(result, familyCode: familyCode) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 44)
        .disabled(authService.isLoading)
        .accessibilityLabel("Sign in with Apple")
    }
}

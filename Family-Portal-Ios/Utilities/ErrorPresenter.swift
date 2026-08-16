import Foundation
import OSLog
import SwiftUI

/// One place for "something the user asked for didn't happen".
///
/// Most of these failures were caught into `print` and dropped: the view had
/// already applied the change locally and dismissed, so a rejected sync looked
/// exactly like a successful one. The push methods on `SyncService` only *queue*
/// work — a network outage never reaches a view — so an error that gets here is
/// a genuine "this will never sync", not a transient blip, and is worth
/// interrupting for.
///
/// It lives at app scope rather than per view because the views that raise these
/// errors dismiss themselves in the same breath; an alert owned by a sheet that
/// is already closing never appears.
@Observable
@MainActor
final class ErrorPresenter {

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        /// What the user was trying to do, e.g. "Couldn't Save Measurement".
        let title: String
        let message: String
    }

    private(set) var failure: Failure?

    /// - Parameters:
    ///   - title: names the action that failed, in the user's terms.
    ///   - log: the category the underlying error is recorded under, so the
    ///     detail survives past the alert the user dismisses.
    func report(_ error: Error, title: String, log: Logger = AppLog.ui) {
        log.error("\(title, privacy: .public): \(String(describing: error), privacy: .public)")
        failure = Failure(title: title, message: error.localizedDescription)
    }

    func report(message: String, title: String, log: Logger = AppLog.ui) {
        log.error("\(title, privacy: .public): \(message, privacy: .public)")
        failure = Failure(title: title, message: message)
    }

    func dismiss() {
        failure = nil
    }
}

extension View {
    /// Presents whatever the shared `ErrorPresenter` is holding. Applied once,
    /// at the root of the window.
    func appErrorAlert() -> some View {
        modifier(AppErrorAlert())
    }
}

private struct AppErrorAlert: ViewModifier {
    @Environment(ErrorPresenter.self) private var presenter: ErrorPresenter?

    func body(content: Content) -> some View {
        content.alert(
            presenter?.failure?.title ?? "Something Went Wrong",
            isPresented: Binding(
                get: { presenter?.failure != nil },
                set: { isPresented in
                    if !isPresented { presenter?.dismiss() }
                }
            ),
            presenting: presenter?.failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }
}

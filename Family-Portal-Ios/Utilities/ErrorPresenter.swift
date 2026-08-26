import Foundation
import OSLog
import SwiftUI

/// One place for "something the user asked for didn't happen".
/// The push methods on `SyncService` only queue work, so an error that reaches here is a genuine "this will never sync". App-scoped because the views that raise these dismiss themselves in the same breath.
@Observable
@MainActor
final class ErrorPresenter {

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    private(set) var failure: Failure?

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

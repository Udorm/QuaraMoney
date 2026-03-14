import Foundation
import SwiftData
import Combine

/// Centralized error handling service for the app.
/// Replaces scattered `try?` and `print()` error handling with consistent logging and user-facing alerts.
@MainActor
final class ErrorService: ObservableObject {
    static let shared = ErrorService()

    /// The most recent user-facing error message, displayed via alert in root view.
    @Published var currentError: AppError?

    private init() {}

    /// Handle a persistence error (e.g., failed `context.save()`).
    /// Shows a user-facing alert for critical persistence failures.
    func handlePersistenceError(_ error: Error, context: String) {
        #if DEBUG
        print("[ErrorService] Persistence error in \(context): \(error)")
        #endif
        currentError = AppError(
            title: "Save Failed",
            message: "Your changes may not have been saved. Please try again.",
            underlyingError: error
        )
    }

    /// Handle a non-critical error (logged but not shown to user).
    func handleError(_ error: Error, context: String) {
        #if DEBUG
        print("[ErrorService] \(context): \(error)")
        #endif
    }

    /// Dismiss the current error alert.
    func dismiss() {
        currentError = nil
    }
}

/// A user-facing error model for alert presentation.
struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let underlyingError: Error?
}

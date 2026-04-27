import Foundation

// MARK: - Shared types

enum LMSImportAvailability: Equatable {
    case available
    case blocked(reason: String)
}

enum LMSImportError: LocalizedError {
    case unavailable
    case canceled
    case invalidCallback
    case notAuthenticated
    case badResponse
    case decodeFailed
    case network
    case backendUnavailable(message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Import is unavailable right now."
        case .canceled:
            return "Import was canceled."
        case .invalidCallback:
            return "Sign-in did not complete."
        case .notAuthenticated:
            return "Please sign in to import assignments."
        case .badResponse:
            return "Couldn't load assignments right now."
        case .decodeFailed:
            return "Couldn't read assignment data right now."
        case .network:
            return "Connection issue. Please try again in a moment."
        case .backendUnavailable(let message):
            return message
        }
    }
}

// MARK: - Protocol

@MainActor
protocol LMSProvider {
    /// Stable identifier used as the `source` field on imported assignments (e.g. "google_classroom", "canvas").
    var id: String { get }
    /// Human-readable name shown in the UI (e.g. "Google Classroom", "Canvas").
    var displayName: String { get }
    /// SF Symbol name for the integration button.
    var systemImage: String { get }

    func preflightAvailability(isAuthenticated: Bool) async -> LMSImportAvailability
    func connectAndFetchAssignments(
        existingExternalIds: [String],
        authToken: String?
    ) async throws -> [ImportedAssignment]
}

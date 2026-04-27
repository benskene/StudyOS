import Foundation
import AuthenticationServices
import UIKit
import OSLog

@MainActor
final class GoogleClassroomProvider: NSObject, LMSProvider {
    private static let logger = Logger(subsystem: "Struc", category: "GoogleClassroomImport")
    private var authSession: ASWebAuthenticationSession?

    let id = "google_classroom"
    let displayName = "Google Classroom"
    let systemImage = "graduationcap"

    var backendBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "StrucBackendBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

    func preflightAvailability(isAuthenticated: Bool) async -> LMSImportAvailability {
        guard isAuthenticated else {
            return .blocked(reason: "Sign in to Struc before importing assignments.")
        }

        do {
            try await verifyBackendHealth()
            return .available
        } catch let error as LMSImportError {
            let reason = error.errorDescription ?? "Google Classroom import is unavailable right now."
            Self.logger.error("Import preflight failed: \(reason, privacy: .public)")
            return .blocked(reason: reason)
        } catch {
            let reason = "Backend not reachable. Set StrucBackendBaseURL and run the backend."
            Self.logger.error("Import preflight failed unexpectedly: \(error.localizedDescription, privacy: .public)")
            return .blocked(reason: reason)
        }
    }

    func connectAndFetchAssignments(
        existingExternalIds: [String],
        authToken: String?
    ) async throws -> [ImportedAssignment] {
        try await startOAuthSession(authToken: authToken)
        return try await fetchAssignments(existingExternalIds: existingExternalIds, authToken: authToken)
    }

    /// Fetches new assignments silently using stored backend tokens — no OAuth UI.
    /// Returns nil if Google Classroom is not connected (no stored tokens on backend).
    func silentFetchIfConnected(
        existingExternalIds: [String],
        authToken: String?
    ) async -> [ImportedAssignment]? {
        do {
            return try await fetchAssignments(existingExternalIds: existingExternalIds, authToken: authToken)
        } catch LMSImportError.notAuthenticated {
            return nil
        } catch LMSImportError.badResponse {
            // 400 = Google Classroom not connected yet
            return nil
        } catch {
            Self.logger.info("Silent Google Classroom sync skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func verifyBackendHealth() async throws {
        guard let healthURL = URL(string: "/health", relativeTo: backendBaseURL) else {
            throw LMSImportError.unavailable
        }
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LMSImportError.backendUnavailable(
                message: "Backend not reachable. Set StrucBackendBaseURL and run the backend."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LMSImportError.backendUnavailable(
                message: "Google Classroom backend is unhealthy right now. Please try again later."
            )
        }
    }

    private func startOAuthSession(authToken: String?) async throws {
        guard let authToken else {
            throw LMSImportError.notAuthenticated
        }
        guard let startURL = URL(string: "/auth/google/start", relativeTo: backendBaseURL) else {
            throw LMSImportError.unavailable
        }
        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let startData: Data
        let startResponse: URLResponse
        do {
            (startData, startResponse) = try await URLSession.shared.data(for: startRequest)
        } catch {
            Self.logger.error("OAuth start request failed: \(error.localizedDescription, privacy: .public)")
            throw LMSImportError.network
        }

        guard let httpStartResponse = startResponse as? HTTPURLResponse,
              (200...299).contains(httpStartResponse.statusCode),
              let payload = try? JSONDecoder().decode(AuthStartResponse.self, from: startData),
              let authURL = URL(string: payload.authUrl) else {
            Self.logger.error("OAuth start response was invalid.")
            throw LMSImportError.badResponse
        }

        try await launchOAuthSession(authURL: authURL)
    }

    private func launchOAuthSession(authURL: URL) async throws {
        let callbackScheme = "studyos"

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] url, error in
                self?.authSession = nil

                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: LMSImportError.canceled)
                        return
                    }
                    Self.logger.error("OAuth browser flow failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: LMSImportError.network)
                    return
                }

                guard let url else {
                    continuation.resume(throwing: LMSImportError.invalidCallback)
                    return
                }

                continuation.resume(returning: url)
            }

            authSession?.prefersEphemeralWebBrowserSession = false
            authSession?.presentationContextProvider = AuthenticationPresentationContextProvider.shared

            if authSession?.start() == false {
                continuation.resume(throwing: LMSImportError.unavailable)
            }
        }

        guard callbackURL.host == "oauth-success" else {
            let reason = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "reason" })?.value
            Self.logger.error("OAuth callback failed: \(reason ?? callbackURL.absoluteString, privacy: .public)")
            throw LMSImportError.invalidCallback
        }
    }

    private func fetchAssignments(
        existingExternalIds: [String],
        authToken: String?
    ) async throws -> [ImportedAssignment] {
        guard let url = URL(string: "/import/google-classroom", relativeTo: backendBaseURL) else {
            throw LMSImportError.unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        } else {
            throw LMSImportError.notAuthenticated
        }

        let body = ["existingExternalIds": existingExternalIds]
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Self.logger.error("Fetch assignments request failed: \(error.localizedDescription, privacy: .public)")
            throw LMSImportError.network
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            Self.logger.error("Fetch assignments response status invalid.")
            throw LMSImportError.badResponse
        }

        do {
            return try JSONDecoder().decode([ImportedAssignment].self, from: data)
        } catch {
            Self.logger.error("Failed to decode assignment payload: \(error.localizedDescription, privacy: .public)")
            throw LMSImportError.decodeFailed
        }
    }
}

private struct AuthStartResponse: Decodable {
    let authUrl: String
}

private final class AuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthenticationPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

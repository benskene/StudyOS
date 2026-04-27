import Foundation
import OSLog

@MainActor
final class CanvasImportService {
    private static let logger = Logger(subsystem: "Struc", category: "CanvasImport")
    private static let connectedKey = "studyos.canvas.isConnected"

    var isConnected: Bool {
        get { UserDefaults.standard.bool(forKey: Self.connectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.connectedKey) }
    }

    var backendBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "StrucBackendBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

    // MARK: - Connect

    func connect(domain: String, accessToken: String, authToken: String) async throws {
        guard let url = URL(string: "/auth/canvas/connect", relativeTo: backendBaseURL) else {
            throw LMSImportError.unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = ["domain": domain, "accessToken": accessToken]
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Self.logger.error("Canvas connect request failed: \(error.localizedDescription, privacy: .public)")
            throw LMSImportError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw LMSImportError.badResponse
        }

        if http.statusCode == 400 {
            let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw CanvasConnectError.invalidCredentials(decoded?.error ?? "Check your Canvas domain and access token.")
        }

        guard (200...299).contains(http.statusCode) else {
            Self.logger.error("Canvas connect returned \(http.statusCode, privacy: .public)")
            throw LMSImportError.badResponse
        }

        isConnected = true
        Self.logger.info("Canvas connected successfully")
    }

    // MARK: - Fetch Assignments

    func fetchAssignments(
        existingExternalIds: [String],
        authToken: String
    ) async throws -> [ImportedAssignment] {
        guard let url = URL(string: "/import/canvas", relativeTo: backendBaseURL) else {
            throw LMSImportError.unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = ["existingExternalIds": existingExternalIds]
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Self.logger.error("Canvas fetch request failed: \(error.localizedDescription, privacy: .public)")
            throw LMSImportError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw LMSImportError.badResponse
        }

        if http.statusCode == 400 {
            // Canvas not connected on backend
            isConnected = false
            throw LMSImportError.badResponse
        }

        guard (200...299).contains(http.statusCode) else {
            Self.logger.error("Canvas fetch returned \(http.statusCode, privacy: .public)")
            throw LMSImportError.badResponse
        }

        do {
            return try JSONDecoder().decode([ImportedAssignment].self, from: data)
        } catch {
            Self.logger.error("Canvas decode failed: \(error.localizedDescription, privacy: .public)")
            throw LMSImportError.decodeFailed
        }
    }

    /// Fetches silently for background sync. Returns nil if not connected or on any error.
    func silentFetchIfConnected(
        existingExternalIds: [String],
        authToken: String
    ) async -> [ImportedAssignment]? {
        guard isConnected else { return nil }

        do {
            return try await fetchAssignments(existingExternalIds: existingExternalIds, authToken: authToken)
        } catch {
            Self.logger.info("Canvas silent sync skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Disconnect

    func disconnect(authToken: String) async throws {
        guard let url = URL(string: "/auth/canvas/disconnect", relativeTo: backendBaseURL) else {
            throw LMSImportError.unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw LMSImportError.badResponse
            }
        } catch let error as LMSImportError {
            throw error
        } catch {
            Self.logger.error("Canvas disconnect failed: \(error.localizedDescription, privacy: .public)")
            throw LMSImportError.network
        }

        isConnected = false
        Self.logger.info("Canvas disconnected")
    }
}

enum CanvasConnectError: LocalizedError {
    case invalidCredentials(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials(let message):
            return message
        }
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}

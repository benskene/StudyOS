import Foundation
import Combine

@MainActor
final class AuthCoordinator: ObservableObject {
    @Published private(set) var authState: AuthManager.AuthState = .resolving

    private let authManager: AuthManager
    private var cancellables = Set<AnyCancellable>()

    init(authManager: AuthManager) {
        self.authManager = authManager

        authManager.$authState
            .receive(on: DispatchQueue.main)
            .assign(to: &$authState)
    }

    var currentUserId: String? {
        authManager.currentUserId
    }

    func fetchBackendAuthToken() async -> String? {
        await authManager.fetchBackendAuthToken()
    }
}

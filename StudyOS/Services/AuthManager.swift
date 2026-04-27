//
//  AuthManager.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import Foundation
import SwiftUI
import UIKit
import AuthenticationServices
import Combine
import OSLog
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
import Combine
#endif

#if canImport(FirebaseAuth)
typealias AuthUser = FirebaseAuth.User
#else
struct AuthUser: Equatable {}
#endif

@MainActor
final class AuthManager: NSObject, ObservableObject {
    enum AuthProvider: String {
        case apple
        case google
        case email
    }

    enum AuthEvent: Equatable {
        case success(provider: AuthProvider)
        case failure(provider: AuthProvider, message: String)
        case canceled(provider: AuthProvider)
    }

    enum AuthState: Equatable {
        case resolving
        case signedOut
        case signedIn(userId: String)
        case error(message: String)
    }

    enum AuthError: LocalizedError {
        case unavailable
        case missingClientID
        case missingRootViewController
        case invalidAppleCredential
        case firebaseFailure(message: String)
        case canceled

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Authentication is unavailable on this build."
            case .missingClientID:
                return "Missing Firebase Google client ID."
            case .missingRootViewController:
                return "Could not present sign-in flow."
            case .invalidAppleCredential:
                return "Apple credential was invalid."
            case .firebaseFailure(let message):
                return message
            case .canceled:
                return "Sign-in canceled."
            }
        }
    }

    enum DeleteAccountError: LocalizedError {
        case notSignedIn
        case requiresRecentLogin
        case unavailable
        case other(message: String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "No signed-in account found."
            case .requiresRecentLogin: return "For your security, please sign in again before deleting your account."
            case .unavailable: return "Account deletion is unavailable in this build."
            case .other(let message): return message
            }
        }
    }

    @Published private(set) var user: AuthUser? = nil
    @Published private(set) var authState: AuthState = .resolving
    @Published private(set) var lastAuthErrorMessage: String?
    @Published private(set) var lastAuthEvent: AuthEvent?

    #if canImport(FirebaseAuth)
    private var authStateListener: AuthStateDidChangeListenerHandle?
    #endif
    private static let logger = Logger(subsystem: "Struc", category: "Auth")
    private static let lastKnownUserIdKey = "Struc.Auth.LastKnownUserId"
    private static let lastResolvedAtKey = "Struc.Auth.LastResolvedAt"
    private var appleSignInContinuation: CheckedContinuation<Result<Void, AuthError>, Never>?

    override init() {
        super.init()
        configureFirebaseIfNeeded()
        restoreLastKnownAuthSnapshot()
        #if canImport(FirebaseAuth)
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.handleFirebaseAuthStateChange(user: user)
        }
        #else
        authState = .signedOut
        #endif
    }

    var isGoogleSignInAvailable: Bool {
        #if canImport(GoogleSignIn) && canImport(FirebaseAuth) && canImport(FirebaseCore)
        return FirebaseApp.app()?.options.clientID?.isEmpty == false
        #else
        return false
        #endif
    }

    var isAppleSignInAvailable: Bool {
        #if canImport(FirebaseAuth)
        return true
        #else
        return false
        #endif
    }

    func unavailableProviderReason(for provider: AuthProvider) -> String? {
        switch provider {
        case .google:
            return isGoogleSignInAvailable ? nil : "Google sign-in is unavailable in this build. Configure Firebase + Google Sign-In to enable it."
        case .apple:
            return isAppleSignInAvailable ? nil : "Apple sign-in is unavailable in this build."
        case .email:
            #if canImport(FirebaseAuth)
            return nil
            #else
            return "Email sign-in is unavailable in this build."
            #endif
        }
    }

    func clearLastAuthEvent() {
        lastAuthEvent = nil
    }

    deinit {
        #if canImport(FirebaseAuth)
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
        #endif
    }

    func signInWithApple() async -> Result<Void, AuthError> {
        #if canImport(FirebaseAuth)
        guard isAppleSignInAvailable else {
            let message = unavailableProviderReason(for: .apple) ?? AuthError.unavailable.localizedDescription
            return registerFailure(provider: .apple, message: message)
        }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return await withCheckedContinuation { continuation in
            appleSignInContinuation = continuation
            controller.performRequests()
        }
        #else
        return registerFailure(provider: .apple, message: AuthError.unavailable.localizedDescription)
        #endif
    }

    func signInWithGoogle() async -> Result<Void, AuthError> {
        #if canImport(GoogleSignIn) && canImport(FirebaseAuth) && canImport(FirebaseCore)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            return registerFailure(provider: .google, error: .missingClientID)
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return registerFailure(provider: .google, error: .missingRootViewController)
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            let user = result.user
            guard let idToken = user.idToken?.tokenString else {
                let message = "Google sign-in failed: missing ID token."
                return registerFailure(provider: .google, message: message)
            }

            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
            _ = try await Auth.auth().signIn(with: credential)
            lastAuthEvent = .success(provider: .google)
            return .success(())
        } catch {
            if error.localizedDescription.lowercased().contains("canceled") {
                let message = AuthError.canceled.localizedDescription
                lastAuthErrorMessage = message
                authState = .error(message: message)
                lastAuthEvent = .canceled(provider: .google)
                Self.logger.error("\(message, privacy: .public)")
                return .failure(.canceled)
            }
            let message = "Google sign-in failed: \(error.localizedDescription)"
            return registerFailure(provider: .google, message: message)
        }
        #else
        // Never silently fall back to anonymous auth from a Google button tap.
        // This keeps "Sync enabled" tied to a verified, user-initiated provider sign-in.
        let message = unavailableProviderReason(for: .google) ?? AuthError.unavailable.localizedDescription
        return registerFailure(provider: .google, message: message)
        #endif
    }

    func signInWithEmail(email: String, password: String) async -> Result<Void, AuthError> {
        #if canImport(FirebaseAuth)
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            lastAuthEvent = .success(provider: .email)
            return .success(())
        } catch {
            let message = "Email sign-in failed: \(error.localizedDescription)"
            return registerFailure(provider: .email, message: message)
        }
        #else
        return registerFailure(provider: .email, message: AuthError.unavailable.localizedDescription)
        #endif
    }

    func signUpWithEmail(email: String, password: String) async -> Result<Void, AuthError> {
        #if canImport(FirebaseAuth)
        do {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
            lastAuthEvent = .success(provider: .email)
            return .success(())
        } catch {
            let message = "Email sign-up failed: \(error.localizedDescription)"
            return registerFailure(provider: .email, message: message)
        }
        #else
        return registerFailure(provider: .email, message: AuthError.unavailable.localizedDescription)
        #endif
    }

    func signOut() -> Result<Void, AuthError> {
        #if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
        } catch {
            let message = "Sign out failed: \(error.localizedDescription)"
            Self.logger.error("\(message, privacy: .public)")
            authState = .error(message: message)
            return .failure(.firebaseFailure(message: message))
        }
        #endif
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        clearAuthPersistence()
        authState = .signedOut
        lastAuthErrorMessage = nil
        lastAuthEvent = nil
        return .success(())
    }

    func deleteAccount() async -> Result<Void, DeleteAccountError> {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let user = Auth.auth().currentUser else {
            return .failure(.notSignedIn)
        }
        let uid = user.uid
        let db = Firestore.firestore()
        do {
            // Delete subcollections first, then the user document
            try await deleteFirestoreCollection(db.collection("users").document(uid).collection("assignments"))
            try await deleteFirestoreCollection(db.collection("users").document(uid).collection("sprints"))
            try? await db.collection("users").document(uid).delete()

            // Delete the Firebase Auth account
            try await user.delete()
            _ = signOut()
            return .success(())
        } catch {
            let nsError = error as NSError
            if let authErrorCode = AuthErrorCode(rawValue: nsError.code),
               authErrorCode.code == .requiresRecentLogin {
                return .failure(.requiresRecentLogin)
            }
            return .failure(.other(message: error.localizedDescription))
        }
        #else
        return .failure(.unavailable)
        #endif
    }

    #if canImport(FirebaseFirestore)
    private func deleteFirestoreCollection(_ ref: CollectionReference) async throws {
        let snapshot = try await ref.getDocuments()
        for document in snapshot.documents {
            try await document.reference.delete()
        }
    }
    #endif

    var currentUserId: String? {
        #if canImport(FirebaseAuth)
        return Auth.auth().currentUser?.uid
        #else
        return nil
        #endif
    }

    func fetchBackendAuthToken() async -> String? {
        #if canImport(FirebaseAuth)
        return try? await Auth.auth().currentUser?.getIDToken()
        #else
        return nil
        #endif
    }

    private func configureFirebaseIfNeeded() {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #endif
    }

    private func restoreLastKnownAuthSnapshot() {
        let lastUserId = UserDefaults.standard.string(forKey: Self.lastKnownUserIdKey)
        if let lastUserId, !lastUserId.isEmpty {
            authState = .signedIn(userId: lastUserId)
        } else {
            authState = .signedOut
        }
    }

    private func persistAuthResolution(userId: String?) {
        if let userId {
            UserDefaults.standard.set(userId, forKey: Self.lastKnownUserIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastKnownUserIdKey)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastResolvedAtKey)
    }

    private func clearAuthPersistence() {
        UserDefaults.standard.removeObject(forKey: Self.lastKnownUserIdKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastResolvedAtKey)
    }

    private func registerFailure(provider: AuthProvider, error: AuthError) -> Result<Void, AuthError> {
        Self.logger.error("\(error.localizedDescription, privacy: .public)")
        authState = .error(message: error.localizedDescription)
        lastAuthErrorMessage = error.localizedDescription
        lastAuthEvent = .failure(provider: provider, message: error.localizedDescription)
        return .failure(error)
    }

    @discardableResult
    private func registerFailure(provider: AuthProvider, message: String) -> Result<Void, AuthError> {
        Self.logger.error("\(message, privacy: .public)")
        authState = .error(message: message)
        lastAuthErrorMessage = message
        lastAuthEvent = .failure(provider: provider, message: message)
        return .failure(.firebaseFailure(message: message))
    }

    #if canImport(FirebaseAuth)
    private func handleFirebaseAuthStateChange(user: FirebaseAuth.User?) {
        self.user = user
        let userId = user?.uid
        persistAuthResolution(userId: userId)
        if let userId {
            authState = .signedIn(userId: userId)
            lastAuthErrorMessage = nil
        } else {
            authState = .signedOut
        }
    }
    #endif
}

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        #if canImport(FirebaseAuth)
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            let error: AuthError = .invalidAppleCredential
            _ = registerFailure(provider: .apple, error: error)
            appleSignInContinuation?.resume(returning: .failure(error))
            appleSignInContinuation = nil
            return
        }

        let credential = OAuthProvider.appleCredential(withIDToken: tokenString, rawNonce: nil, fullName: appleIDCredential.fullName)
        Task {
            do {
                _ = try await Auth.auth().signIn(with: credential)
                lastAuthEvent = .success(provider: .apple)
                appleSignInContinuation?.resume(returning: .success(()))
                appleSignInContinuation = nil
            } catch {
                let message = "Apple sign-in failed: \(error.localizedDescription)"
                _ = registerFailure(provider: .apple, message: message)
                appleSignInContinuation?.resume(returning: .failure(.firebaseFailure(message: message)))
                appleSignInContinuation = nil
            }
        }
        #else
        appleSignInContinuation?.resume(returning: .failure(.unavailable))
        appleSignInContinuation = nil
        #endif
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        let authError: AuthError = nsError.domain == ASAuthorizationError.errorDomain && nsError.code == ASAuthorizationError.canceled.rawValue
            ? .canceled
            : .firebaseFailure(message: error.localizedDescription)
        if case .canceled = authError {
            let message = authError.localizedDescription
            Self.logger.error("\(message, privacy: .public)")
            authState = .error(message: message)
            lastAuthErrorMessage = message
            lastAuthEvent = .canceled(provider: .apple)
        } else {
            _ = registerFailure(provider: .apple, message: authError.localizedDescription)
        }
        appleSignInContinuation?.resume(returning: .failure(authError))
        appleSignInContinuation = nil
    }
}

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}


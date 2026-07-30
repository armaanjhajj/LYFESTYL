//
//  AuthManager.swift
//  LYFESTYL
//
//  Sign in with Apple gates the app; CloudKit's private database (auto scoped to
//  the signed in iCloud account) holds the data. There is no backend token
//  exchange and no external service: the Apple credential establishes the local
//  session, and every entry lives in the user's own iCloud.
//
//  A stable local user id (persisted once) tags the offline cache. Apple only
//  returns the full name on the first sign in, so we persist it when we get it.
//

import Foundation
import Observation
import AuthenticationServices
import CloudKit

@MainActor
@Observable
final class AuthManager {

    enum Phase: Equatable {
        case loading      // resolving the persisted session
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .loading
    private(set) var userID: UUID?
    private(set) var displayName: String?
    var errorMessage: String?

    /// CloudKit needs no secrets, so the app is always "configured". Kept so the
    /// existing root routing (which branches on this) stays intact.
    var isConfigured: Bool { true }

    private enum Key {
        static let appleUserID = "auth.appleUserID"
        static let displayName = "auth.displayName"
        static let localUserID = "auth.localUserID"
    }

    private let defaults = UserDefaults.standard

    init() {
        #if DEBUG
        if SampleData.isPreview {
            userID = SampleData.userID
            displayName = "Preview"
            phase = .signedIn
            return
        }
        #endif
        Task { await restoreSession() }
    }

    // MARK: - Apple sign-in

    /// Configure the Apple request: the scopes we want. No server nonce is needed
    /// because there is no backend to exchange the token with, the credential
    /// simply establishes the local session over the user's iCloud data.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    /// Handle the SignInWithAppleButton completion: persist the stable Apple user
    /// id and the display name, establish the local session, and flag if iCloud is
    /// unavailable (non blocking, entries are always safe on device).
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return // user canceled, not an error worth surfacing
            }
            errorMessage = "Sign in failed. \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Sign in failed: unexpected credential."
                return
            }
            defaults.set(credential.user, forKey: Key.appleUserID)

            // Apple only returns the name on the first sign in; persist it if present.
            if let fullName = credential.fullName {
                let name = PersonNameComponentsFormatter()
                    .string(from: fullName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { defaults.set(name, forKey: Key.displayName) }
            }
            displayName = defaults.string(forKey: Key.displayName) ?? credential.email

            userID = localUserID()
            errorMessage = nil
            phase = .signedIn

            await warnIfNoAccount()
        }
    }

    func signOut() async {
        defaults.removeObject(forKey: Key.appleUserID)
        defaults.removeObject(forKey: Key.displayName)
        userID = nil
        displayName = nil
        errorMessage = nil
        phase = .signedOut
    }

    // MARK: - Session restore

    /// Restore a persisted session on launch: if we have a stored Apple user id and
    /// it is still authorized, sign back in; otherwise show the sign in gate.
    private func restoreSession() async {
        guard let appleUserID = defaults.string(forKey: Key.appleUserID) else {
            phase = .signedOut
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        let state = try? await provider.credentialState(forUserID: appleUserID)
        switch state {
        case .authorized:
            userID = localUserID()
            displayName = defaults.string(forKey: Key.displayName)
            phase = .signedIn
            await warnIfNoAccount()
        default:
            // Revoked, transferred, or not found: clear and require sign in again.
            defaults.removeObject(forKey: Key.appleUserID)
            defaults.removeObject(forKey: Key.displayName)
            phase = .signedOut
        }
    }

    // MARK: - Helpers

    /// A stable, app local user id used only to tag the offline cache. The
    /// authoritative scoping is CloudKit's private DB (the iCloud account itself).
    private func localUserID() -> UUID {
        if let raw = defaults.string(forKey: Key.localUserID), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Key.localUserID)
        return id
    }

    /// Best effort: surface a calm hint if iCloud isn't available, so the user
    /// knows sync is paused. Never blocks sign in, the local cache is authoritative
    /// on device until iCloud returns.
    private func warnIfNoAccount() async {
        let status = try? await CKContainer.default().accountStatus()
        if status != .available {
            errorMessage = "Signed in. Sign into iCloud in Settings to sync your entries across devices."
        }
    }
}

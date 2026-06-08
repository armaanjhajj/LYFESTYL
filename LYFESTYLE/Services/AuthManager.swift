//
//  AuthManager.swift
//  LYFESTYL
//
//  Sign in with Apple → Supabase Auth (CLAUDE.md §4.3). Owns auth state and
//  gates the app. The nonce flow is security-critical and verified:
//    • generate a RAW nonce
//    • set sha256(raw) (HASHED) on the Apple request
//    • pass the RAW nonce to Supabase signInWithIdToken
//

import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import Supabase

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

    /// False when Secrets.plist is missing/placeholder — the UI shows a setup screen.
    var isConfigured: Bool { SupabaseConfig.isConfigured }

    private let client = SupabaseConfig.client
    private var currentNonce: String?
    private var pendingDisplayName: String?
    private var authTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if SampleData.isPreview {
            userID = SampleData.userID
            displayName = "Preview"
            phase = .signedIn
            return
        }
        #endif
        guard let client else {
            // Not configured — surface a setup state, don't crash.
            phase = .signedOut
            return
        }
        authTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                await self?.apply(event: event, session: session)
            }
        }
    }

    // MARK: - Apple sign-in

    /// Configure the Apple request: scopes + the HASHED nonce.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let raw = Self.randomNonceString()
        currentNonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(raw)
    }

    /// Handle the SignInWithAppleButton completion: extract the id token and
    /// exchange it with Supabase using the RAW nonce.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return // user canceled — not an error worth surfacing
            }
            errorMessage = "Sign in failed. \(error.localizedDescription)"
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = "Sign in failed: missing identity token."
                return
            }
            if let fullName = credential.fullName {
                let name = PersonNameComponentsFormatter()
                    .string(from: fullName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { pendingDisplayName = name }
            }
            do {
                guard let client else { throw AuthError.notConfigured }
                _ = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                // session arrival handled by the authStateChanges stream
            } catch {
                errorMessage = "Sign in failed. \(error.localizedDescription)"
            }
        }
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
        userID = nil
        displayName = nil
        phase = .signedOut
    }

    // MARK: - State

    private func apply(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedOut:
            userID = nil
            displayName = nil
            phase = .signedOut
        default:
            if let user = session?.user {
                userID = user.id
                phase = .signedIn
                await syncProfileIfNeeded(userID: user.id, email: user.email)
            } else if event == .initialSession {
                // No persisted session.
                phase = .signedOut
            }
        }
    }

    private func syncProfileIfNeeded(userID: UUID, email: String?) async {
        // Apple only returns the name on first sign-in; persist it if we got one.
        if let name = pendingDisplayName {
            displayName = name
            if let service = SupabaseService() {
                await service.upsertProfile(userID: userID, displayName: name)
            }
            pendingDisplayName = nil
        } else if displayName == nil {
            displayName = email
        }
    }

    enum AuthError: LocalizedError {
        case notConfigured
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase isn't configured. Add your keys to Secrets.plist."
            }
        }
    }

    // MARK: - Nonce helpers (verified)

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess { continue }
            for random in randoms where remaining > 0 {
                if random < charset.count * (256 / charset.count) {
                    result.append(charset[Int(random) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

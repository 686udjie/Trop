//
//  DiscordAuth.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct DiscordAuthResult {
    let accessToken: String
    let refreshToken: String
    let expiresInSec: Int64
    let scope: String
}

struct PkcePair {
    let verifier: String
    let challenge: String
}

enum DiscordAuthError: Error, LocalizedError {
    case userCancelled
    case networkFailure(Error)
    case invalidGrant
    case stateMismatch
    case noBrowser
    case missingCode

    var errorDescription: String? {
        switch self {
        case .userCancelled: return "Authorization cancelled"
        case .networkFailure(let e): return "Network failure: \(e.localizedDescription)"
        case .invalidGrant: return "Invalid grant"
        case .stateMismatch: return "State mismatch"
        case .noBrowser: return "No browser available"
        case .missingCode: return "Missing authorization code"
        }
    }
}

final class DiscordAuth: NSObject {
    static let redirectUri = DiscordDefaults.redirectUri

    private var currentSession: ASWebAuthenticationSession?
    private var authProvider: PresentationContextProvider?
    private var pendingContinuation: CheckedContinuation<URL, Error>?

    // MARK: - PKCE

    static func generatePkcePair() -> PkcePair {
        var bytes = Data(count: 64)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 64, $0.baseAddress!) }
        let verifier = bytes.base64URLEncodedNoPadding
        let challenge = Data(verifier.utf8).sha256Base64URLEncoded
        return PkcePair(verifier: verifier, challenge: challenge)
    }

    private static func generateState() -> String {
        var bytes = Data(count: 16)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return bytes.base64URLEncodedNoPadding
    }

    static func buildAuthorizeUrl(
        clientId: String,
        redirectUri: String,
        state: String,
        challenge: String
    ) -> String {
        let encodedRedirect = redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectUri
        let encodedScope = DiscordDefaults.scopes.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? DiscordDefaults.scopes
        return "\(DiscordDefaults.oauthAuthorize)?client_id=\(clientId)&response_type=code"
            + "&redirect_uri=\(encodedRedirect)&scope=\(encodedScope)&state=\(state)"
            + "&code_challenge_method=S256&code_challenge=\(challenge)"
    }

    // MARK: - Authorize (browser)

    @MainActor
    func authorize(presentingAnchor: ASPresentationAnchor? = nil) async throws -> DiscordAuthResult {
        let pkce = Self.generatePkcePair()
        let state = Self.generateState()
        let urlString = Self.buildAuthorizeUrl(
            clientId: DiscordDefaults.appId,
            redirectUri: Self.redirectUri,
            state: state,
            challenge: pkce.challenge
        )
        guard let url = URL(string: urlString) else { throw DiscordAuthError.noBrowser }

        let callbackScheme = DiscordDefaults.redirectScheme

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    cont.resume(throwing: DiscordAuthError.userCancelled)
                    return
                }
                if let error = error {
                    cont.resume(throwing: DiscordAuthError.networkFailure(error))
                    return
                }
                guard let callbackURL = callbackURL else {
                    cont.resume(throwing: DiscordAuthError.missingCode)
                    return
                }
                cont.resume(returning: callbackURL)
            }
            // Must retain session and provider (provider is weak on session)
            let provider: PresentationContextProvider
            if let anchor = presentingAnchor {
                provider = PresentationContextProvider(anchor: anchor)
            } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let window = windowScene.windows.first {
                provider = PresentationContextProvider(anchor: window)
            } else {
                guard let fallbackScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                    cont.resume(throwing: DiscordAuthError.noBrowser)
                    return
                }
                provider = PresentationContextProvider(anchor: UIWindow(windowScene: fallbackScene))
            }
            self.authProvider = provider
            session.presentationContextProvider = provider
            self.currentSession = session
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        currentSession = nil
        authProvider = nil

        // Parse query items
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw DiscordAuthError.missingCode
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            throw DiscordAuthError.userCancelled
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw DiscordAuthError.missingCode
        }
        let returnedState = items.first(where: { $0.name == "state" })?.value ?? ""
        guard returnedState == state else { throw DiscordAuthError.stateMismatch }

        return try await exchangeAuthorizationCode(code: code, verifier: pkce.verifier, redirectUri: Self.redirectUri)
    }

    func cancel() {
        currentSession?.cancel()
        currentSession = nil
    }

    // MARK: - Token exchange

    func refresh(refreshToken: String) async throws -> DiscordAuthResult {
        try await performTokenExchange(grantType: "refresh_token", extra: ["refresh_token": refreshToken])
    }

    func exchangeAuthorizationCode(code: String, verifier: String, redirectUri: String) async throws -> DiscordAuthResult {
        try await performTokenExchange(grantType: "authorization_code", extra: [
            "code": code,
            "redirect_uri": redirectUri,
            "code_verifier": verifier
        ])
    }

    private func performTokenExchange(grantType: String, extra: [String: String]) async throws -> DiscordAuthResult {
        guard let url = URL(string: DiscordDefaults.oauthToken) else { throw DiscordAuthError.networkFailure(URLError(.badURL)) }
        var components = URLComponents()
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: DiscordDefaults.appId),
            URLQueryItem(name: "grant_type", value: grantType)
        ]
        for (k, v) in extra { items.append(URLQueryItem(name: k, value: v)) }
        components.queryItems = items
        let bodyString = components.percentEncodedQuery ?? ""
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DiscordAuthError.networkFailure(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""

        if (200...299).contains(status) {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String else {
                throw DiscordAuthError.networkFailure(NSError(domain: "DiscordAuth", code: status, userInfo: [NSLocalizedDescriptionKey: body]))
            }
            let refreshToken = json["refresh_token"] as? String ?? ""
            let expiresIn = (json["expires_in"] as? NSNumber)?.int64Value ?? Int64((json["expires_in"] as? Int ?? 0))
            let scope = json["scope"] as? String ?? DiscordDefaults.scopes
            return DiscordAuthResult(accessToken: accessToken, refreshToken: refreshToken, expiresInSec: expiresIn, scope: scope)
        }

        var errorCode = ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            errorCode = json["error"] as? String ?? ""
        }
        if status == 400, errorCode == "invalid_grant" {
            throw DiscordAuthError.invalidGrant
        }
        throw DiscordAuthError.networkFailure(
            NSError(domain: "DiscordAuth", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status): \(body)"])
        )
    }
}

// MARK: - Helpers

private extension Data {
    var base64URLEncodedNoPadding: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    var sha256Base64URLEncoded: String {
        let hash = SHA256.hash(data: self)
        return Data(hash).base64URLEncodedNoPadding
    }
}

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}

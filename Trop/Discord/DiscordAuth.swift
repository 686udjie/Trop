//
//  DiscordAuth.swift
//  Trop
//

import CryptoKit
import Foundation
import Security
@preconcurrency import SwiftUI
import UIKit
import WebKit

struct DiscordAuthResult: Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresInSec: Int64
    var scope: String
}

enum DiscordAuthError: Error, LocalizedError {
    case missingClientId
    case userCancelled
    case stateMismatch
    case invalidGrant
    case network(String)
    case missingCode

    var errorDescription: String? {
        switch self {
        case .missingClientId:
            return "Discord Client ID is not configured in Trop.plist"
        case .userCancelled:
            return "Authorization cancelled"
        case .stateMismatch:
            return "OAuth state mismatch"
        case .invalidGrant:
            return "Invalid or expired grant"
        case .network(let message):
            return message
        case .missingCode:
            return "Missing authorization code"
        }
    }
}

/// PKCE OAuth2 for Discord Social Layer presence.
@MainActor
enum DiscordAuth {
    private static var pendingContinuation: CheckedContinuation<URL, Error>?
    private static var expectedState: String?

    static func handleRedirectURL(_ url: URL) -> Bool {
        guard url.scheme == "trop",
              url.host == "oauth2",
              url.path.hasPrefix("/callback") || url.path == "/callback" || url.absoluteString.contains("oauth2/callback") else {
            return false
        }
        guard let continuation = pendingContinuation else { return false }
        pendingContinuation = nil
        continuation.resume(returning: url)
        return true
    }

    static func cancelPending() {
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            continuation.resume(throwing: DiscordAuthError.userCancelled)
        }
        expectedState = nil
    }

    static func authorize(clientId: String) async throws -> DiscordAuthResult {
        guard !clientId.isEmpty else { throw DiscordAuthError.missingClientId }
        let pkce = generatePkce()
        let state = randomURLSafe(32)
        expectedState = state

        let authURL = buildAuthorizeURL(clientId: clientId, state: state, challenge: pkce.challenge)
        let callbackURL = try await waitForCallback(authURL: authURL)
        expectedState = nil

        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let items = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )
        if let error = items["error"] {
            throw DiscordAuthError.network(error)
        }
        guard let code = items["code"], !code.isEmpty else {
            throw DiscordAuthError.missingCode
        }
        if items["state"] != state {
            throw DiscordAuthError.stateMismatch
        }
        return try await exchangeCode(code: code, verifier: pkce.verifier, clientId: clientId)
    }

    static func refresh(refreshToken: String, clientId: String) async throws -> DiscordAuthResult {
        guard !clientId.isEmpty else { throw DiscordAuthError.missingClientId }
        var body: [String: String] = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        return try await tokenRequest(body: &body)
    }

    // MARK: - Private

    private static func waitForCallback(authURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            pendingContinuation = continuation
            NotificationCenter.default.post(
                name: .discordAuthPresentWebView,
                object: nil,
                userInfo: ["url": authURL]
            )
        }
    }

    private static func exchangeCode(
        code: String,
        verifier: String,
        clientId: String
    ) async throws -> DiscordAuthResult {
        var body: [String: String] = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": DiscordDefaults.redirectURI,
            "code_verifier": verifier
        ]
        return try await tokenRequest(body: &body)
    }

    private static func tokenRequest(body: inout [String: String]) async throws -> DiscordAuthResult {
        guard let url = URL(string: DiscordDefaults.oauthToken) else {
            throw DiscordAuthError.network("Invalid token URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Trop (https://github.com/686udjie/Trop)", forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DiscordAuthError.network("Invalid response")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (200..<300).contains(http.statusCode) {
            guard let access = json["access_token"] as? String else {
                throw DiscordAuthError.network("Missing access_token")
            }
            return DiscordAuthResult(
                accessToken: access,
                refreshToken: json["refresh_token"] as? String ?? "",
                expiresInSec: (json["expires_in"] as? NSNumber)?.int64Value ?? 0,
                scope: json["scope"] as? String ?? DiscordDefaults.scopes
            )
        }
        if http.statusCode == 400, json["error"] as? String == "invalid_grant" {
            throw DiscordAuthError.invalidGrant
        }
        let message = json["error_description"] as? String
            ?? json["error"] as? String
            ?? "HTTP \(http.statusCode)"
        throw DiscordAuthError.network(message)
    }

    private static func buildAuthorizeURL(clientId: String, state: String, challenge: String) -> URL {
        var components = URLComponents(string: DiscordDefaults.oauthAuthorize)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: DiscordDefaults.redirectURI),
            URLQueryItem(name: "scope", value: DiscordDefaults.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "none")
        ]
        return components.url!
    }

    private static func generatePkce() -> (verifier: String, challenge: String) {
        let verifier = randomURLSafe(64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return (verifier, challenge)
    }

    private static func randomURLSafe(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let encoded = Data(bytes).base64URLEncodedString()
        return String(encoded.prefix(length))
    }

    private static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        let pairs = params.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

extension Notification.Name {
    static let discordAuthPresentWebView = Notification.Name("trop.discord.auth.presentWebView")
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Auth WebView

struct DiscordOAuthWebView: View {
    let authURL: URL
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            DiscordOAuthPresenter(authURL: authURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Discord")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            DiscordAuth.cancelPending()
                            onCancel()
                        }
                    }
                }
        }
    }
}

private struct DiscordOAuthPresenter: UIViewControllerRepresentable {
    typealias UIViewControllerType = DiscordOAuthController

    let authURL: URL

    func makeUIViewController(
        context: UIViewControllerRepresentableContext<DiscordOAuthPresenter>
    ) -> DiscordOAuthController {
        DiscordOAuthController(authURL: authURL)
    }

    func updateUIViewController(
        _ uiViewController: DiscordOAuthController,
        context: UIViewControllerRepresentableContext<DiscordOAuthPresenter>
    ) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {}
}

final class DiscordOAuthController: UIViewController {
    private let authURL: URL
    private var navigationDelegate: DiscordOAuthNavigationDelegate?

    init(authURL: URL) {
        self.authURL = authURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let delegate = DiscordOAuthNavigationDelegate()
        navigationDelegate = delegate
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = delegate
        view = webView
        webView.load(URLRequest(url: authURL))
    }
}

private final class DiscordOAuthNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, DiscordAuth.handleRedirectURL(url) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

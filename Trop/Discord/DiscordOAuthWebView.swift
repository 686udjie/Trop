//
//  DiscordOAuthWebView.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import SwiftUI
import WebKit
import OSLog
import CryptoKit

struct DiscordOAuthWebView: View {
    var onComplete: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pkce: PkcePair = DiscordAuth.generatePkcePair()
    @State private var state: String = {
        var bytes = Data(count: 16)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }()
    @State private var isExchanging = false
    @State private var errorText: String?

    private var authUrl: String {
        DiscordAuth.buildAuthorizeUrl(
            clientId: DiscordDefaults.appId,
            redirectUri: DiscordDefaults.redirectUri,
            state: state,
            challenge: pkce.challenge
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WebViewContainer(
                    urlString: authUrl,
                    pkceVerifier: pkce.verifier,
                    oauthState: state,
                    isExchanging: $isExchanging,
                    errorText: $errorText,
                    onComplete: { success in
                        onComplete(success)
                        dismiss()
                    }
                )
                .ignoresSafeArea()

                if isExchanging {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Completing login…")
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Discord Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onComplete(false)
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                            Text("Close")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if let host = URL(string: authUrl)?.host {
                        Text(host).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button("OK") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .onAppear {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.686udjie.Trop", category: "DiscordSvc")
                    .info("OAuth WebView loading: \(authUrl, privacy: .private)")
            }
        }
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let urlString: String
    let pkceVerifier: String
    let oauthState: String
    @Binding var isExchanging: Bool
    @Binding var errorText: String?
    var onComplete: (Bool) -> Void

    func makeUIView(context: UIViewRepresentableContext<WebViewContainer>) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Discord blocks some embedded agents — use Safari-like UA
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.webViewRef = webView
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: UIViewRepresentableContext<WebViewContainer>) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pkceVerifier: pkceVerifier,
            oauthState: oauthState,
            isExchanging: $isExchanging,
            errorText: $errorText,
            onComplete: onComplete
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let pkceVerifier: String
        let oauthState: String
        let pkceChallenge: String
        @Binding var isExchanging: Bool
        @Binding var errorText: String?
        var onComplete: (Bool) -> Void
        private var didComplete = false
        private var hasRetriedFallback = false
        weak var webViewRef: WKWebView?
        private let log = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.686udjie.Trop",
            category: "DiscordSvc"
        )

        init(
            pkceVerifier: String,
            oauthState: String,
            isExchanging: Binding<Bool>,
            errorText: Binding<String?>,
            onComplete: @escaping (Bool) -> Void
        ) {
            self.pkceVerifier = pkceVerifier
            self.oauthState = oauthState
            // Derive challenge from verifier for fallback reload
            let challenge = Data(pkceVerifier.utf8).sha256Base64URLEncoded
            self.pkceChallenge = challenge
            self._isExchanging = isExchanging
            self._errorText = errorText
            self.onComplete = onComplete
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let str = url.absoluteString
            if str.hasPrefix(DiscordDefaults.redirectUri) {
                decisionHandler(.cancel)
                guard !didComplete else { return }
                didComplete = true
                handleCallback(url: url)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            errorText = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            if let url = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
               url.absoluteString.hasPrefix(DiscordDefaults.redirectUri) {
                return
            }
        }

        private func handleCallback(url: URL) {
            log.info("handleCallback: \(url.absoluteString, privacy: .private)")
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                log.error("bad callback URL")
                onComplete(false)
                return
            }
            let items = comps.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
                let rawDesc = items.first(where: { $0.name == "error_description" })?.value ?? error
                let desc = rawDesc.removingPercentEncoding?.replacingOccurrences(of: "+", with: " ") ?? rawDesc
                log.error(
                    "OAuth error: \(error, privacy: .public) desc=\(desc, privacy: .private) url=\(url.absoluteString, privacy: .private)")
                // swiftlint:disable:next line_length
                log.error("Hint: scope='\(DiscordDefaults.scopes, privacy: .public)' appId=\(DiscordDefaults.appId, privacy: .public) - check Developer Portal")
                if error == "invalid_scope", !hasRetriedFallback, DiscordDefaults.scopes == "openid sdk.social_layer_presence" {
                    log.warning("invalid_scope with primary scopes — retrying with fallback '\(DiscordDefaults.scopesFallback, privacy: .public)'")
                    hasRetriedFallback = true
                    didComplete = false
                    // Persist fallback for token exchange logging
                    UserDefaults.standard.set(DiscordDefaults.scopesFallback, forKey: "discordScopesOverride")
                    let fallbackEncoded = DiscordDefaults.scopesFallback
                        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? DiscordDefaults.scopesFallback
                    let redirectEnc = DiscordDefaults.redirectUri
                        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? DiscordDefaults.redirectUri
                    // swiftlint:disable:next line_length
                    let retryUrlStr = "\(DiscordDefaults.oauthAuthorize)?client_id=\(DiscordDefaults.appId)&response_type=code&redirect_uri=\(redirectEnc)&scope=\(fallbackEncoded)&state=\(oauthState)&code_challenge_method=S256&code_challenge=\(pkceChallenge)"
                    log.info("Retrying OAuth fallback: \(retryUrlStr, privacy: .private)")
                    Task { @MainActor in
                        errorText = "Primary scope rejected, retrying with '\(DiscordDefaults.scopesFallback)'…"
                    }
                    if let retryUrl = URL(string: retryUrlStr), let wv = webViewRef {
                        wv.load(URLRequest(url: retryUrl))
                    }
                    return
                }
                if error == "invalid_scope" {
                    log.error("invalid_scope scopes='\(DiscordDefaults.scopes, privacy: .public)'")
                    log.error("Portal: add tropdiscord://oauth2/callback + enable openid sdk.social_layer_presence")
                }
                Task { @MainActor in
                    var hint = "Denied (\(error)): \(desc)\nPortal: add tropdiscord://oauth2/callback"
                    if error == "invalid_scope" {
                        hint += "\nScope '\(DiscordDefaults.scopes)' rejected. "
                            + "Fix: enable openid sdk.social_layer_presence or use fallback '\(DiscordDefaults.scopesFallback)'."
                    }
                    errorText = hint
                    // Don't auto-dismiss on invalid_scope retry — let user see hint
                    if hasRetriedFallback {
                        // Already retried, now surface failure without dismissing sheet immediately
                        // Keep sheet open for 1s so alert shows
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                    onComplete(false)
                }
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                log.error("Missing code in callback")
                Task { @MainActor in
                    errorText = "Missing authorization code"
                    onComplete(false)
                }
                return
            }
            let returnedState = items.first(where: { $0.name == "state" })?.value ?? ""
            guard returnedState == oauthState else {
                log.error("State mismatch")
                Task { @MainActor in
                    errorText = "State mismatch"
                    onComplete(false)
                }
                return
            }
            Task { @MainActor in isExchanging = true }
            Task {
                do {
                    let auth = DiscordAuth()
                    let result = try await auth.exchangeAuthorizationCode(
                        code: code,
                        verifier: pkceVerifier,
                        redirectUri: DiscordDefaults.redirectUri
                    )
                    await MainActor.run {
                        DiscordTokenStore.shared.storeFull(
                            accessToken: result.accessToken,
                            refreshToken: result.refreshToken,
                            expiresInSec: result.expiresInSec
                        )
                        DiscordRpcManager.shared.handleWebViewAuth(result: result)
                        isExchanging = false
                        onComplete(true)
                    }
                } catch {
                    log.error("token exchange failed: \(error.localizedDescription, privacy: .private)")
                    await MainActor.run {
                        isExchanging = false
                        errorText = error.localizedDescription
                        onComplete(false)
                    }
                }
            }
        }
    }
}

private extension Data {
    var sha256Base64URLEncoded: String {
        let hash = CryptoKit.SHA256.hash(data: self)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

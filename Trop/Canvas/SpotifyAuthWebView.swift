//
//  SpotifyAuthWebView.swift
//  Trop
//
//  Created by 686udjie on 11/10/2026.
//

import SwiftUI
import WebKit

struct SpotifyAuthWebView: View {
    var onComplete: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var errorText: String?
    @State private var currentHost = "open.spotify.com"

    var body: some View {
        NavigationStack {
            SpotifyLoginContainer(
                currentHost: $currentHost,
                errorText: $errorText,
                onComplete: { success in
                    onComplete(success)
                    dismiss()
                }
            )
            .ignoresSafeArea()
            .navigationTitle("Spotify Login")
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
                    Text(currentHost).font(.caption).foregroundStyle(.secondary)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }
}

private struct SpotifyLoginContainer: UIViewRepresentable {
    @Binding var currentHost: String
    @Binding var errorText: String?
    var onComplete: (Bool) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Persistent: the login session survives, so returning users and
        // token harvests share it instead of signing in every time.
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: CanvasTokenHook.bridgeName)
        config.userContentController.addUserScript(
            WKUserScript(source: CanvasTokenHook.script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.webViewRef = webView
        context.coordinator.startTimeout()
        if let url = URL(string: "https://open.spotify.com/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(currentHost: $currentHost, errorText: $errorText, onComplete: onComplete)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding private var currentHost: String
        @Binding private var errorText: String?
        private var onComplete: (Bool) -> Void

        private let lock = NSLock()
        private var captured: HarvestedCanvasToken?
        private var completing = false
        private var completed = false
        private var pollTask: Task<Void, Never>?
        private var triedProfile = false
        private let deadline = Date().addingTimeInterval(95)
        weak var webViewRef: WKWebView?

        deinit {
            pollTask?.cancel()
        }

        init(currentHost: Binding<String>, errorText: Binding<String?>, onComplete: @escaping (Bool) -> Void) {
            self._currentHost = currentHost
            self._errorText = errorText
            self.onComplete = onComplete
        }

        func startTimeout() {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                guard let self, !self.lock.withLock({ self.completed }) else { return }
                await MainActor.run {
                    self.errorText = "Couldn't confirm the login in time. If you signed in, close and reopen to retry."
                }
            }
        }

        // MARK: Token hook

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? String,
                  let harvested = CanvasTokenHook.parse(payload)
            else { return }
            lock.withLock { captured = harvested }
            if let webView = webViewRef { probe(webView: webView) }
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.currentHost = webView.url?.host ?? "spotify.com"
            }
            ensurePolling(webView: webView)
            probe(webView: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor [weak self] in
                self?.errorText = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor [weak self] in
                self?.errorText = error.localizedDescription
            }
        }

        // MARK: Login probe

        private func ensurePolling(webView: WKWebView) {
            let shouldStart = lock.withLock { () -> Bool in
                guard pollTask == nil, !completed else { return false }
                return true
            }
            guard shouldStart else { return }
            pollTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                while !Task.isCancelled {
                    if self.lock.withLock({ self.completed }) { break }
                    if Date() > self.deadline {
                        await MainActor.run {
                            if self.errorText == nil {
                                self.errorText = "Still waiting — if you signed in, close and reopen to retry."
                            }
                        }
                        break
                    }
                    self.probe(webView: webView)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                self.lock.withLock { self.pollTask = nil }
            }
        }

        /// Confirms the login: `sp_dc` cookie present and `/v1/me` answering
        /// for a bearer from this session. Either signal alone is not enough —
        /// a logged-out visitor can hold a cookie-shaped value and an
        /// anonymous token, but only a real login passes both.
        private func probe(webView: WKWebView) {
            let shouldRun = lock.withLock { () -> Bool in
                guard !completed, !completing else { return false }
                completing = true
                return true
            }
            guard shouldRun else { return }
            Task { [weak self] in
                guard let self else { return }
                defer { self.lock.withLock { self.completing = false } }
                let cookies = await Self.readCookies(from: webView.configuration.websiteDataStore)
                guard let spDc = cookies.first(where: { $0.name == "sp_dc" && !$0.value.isEmpty }) else { return }
                var harvested = self.lock.withLock { self.captured }
                if harvested == nil {
                    harvested = await CanvasSpotifyToken.shared.harvestedToken(cookie: spDc.value)
                }
                guard let harvested else { return }
                let token = harvested.token
                let clientId = harvested.clientId
                // The bearer alone earns a 429 here — the client token must
                // ride along, minted from the payload's own client id.
                var client: String?
                if let clientId {
                    client = await CanvasSpotifyToken.shared.clientToken(clientId: clientId)
                }
                // `/v1/me` is quota-guarded (24h bans) and the web client
                // itself never calls it — one attempt per sheet for the
                // profile, then never again. Confirmation runs on the search
                // path regardless.
                let shouldTryProfile = self.lock.withLock { () -> Bool in
                    guard !self.triedProfile else { return false }
                    self.triedProfile = true
                    return true
                }
                if shouldTryProfile,
                   let profile = await SpotifyAccountStore.fetchProfile(token: token, clientToken: client) {
                    SpotifyAccountStore.shared.store(cookie: spDc.value, profile: profile)
                    await CanvasSpotifyToken.shared.seed(harvested)
                    await self.finishLogin()
                    return
                }
                // `/v1/me` stays shut for these tokens, but the web player's
                // own profile query rides the same session — try it before
                // falling back to a session-only confirmation.
                if let profile = await SpotifyCanvas.fetchProfileViaPathfinder(token: token, clientToken: client) {
                    SpotifyAccountStore.shared.store(cookie: spDc.value, profile: profile)
                    await CanvasSpotifyToken.shared.seed(harvested)
                    await self.finishLogin()
                    return
                }
                // `/v1/me` can stay shut for a token the search path still
                // honours — confirm the session that way instead of leaving
                // a working login unclaimed.
                guard await SpotifyCanvas.sessionCheck(token: token, clientToken: client) else { return }
                SpotifyAccountStore.shared.storeSession(cookie: spDc.value)
                await CanvasSpotifyToken.shared.seed(harvested)
                await self.finishLogin()
                return
            }
        }

        /// Marks completion once and dismisses. Split out so both
        /// confirmation routes share the same exactly-once gate. The token
        /// cache is seeded (not invalidated) here so canvas lookups reuse the
        /// just-confirmed bearer instead of cold-harvesting.
        private func finishLogin() async {
            let finished = self.lock.withLock { () -> Bool in
                guard !self.completed else { return false }
                self.completed = true
                return true
            }
            guard finished else { return }
            await MainActor.run { self.onComplete(true) }
        }

        private static func readCookies(from store: WKWebsiteDataStore) async -> [HTTPCookie] {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    store.httpCookieStore.getAllCookies { cookies in
                        continuation.resume(returning: cookies)
                    }
                }
            }
        }
    }
}

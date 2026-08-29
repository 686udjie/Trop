//
//  DiscordLoginWebView.swift
//  Trop
//

@preconcurrency import SwiftUI
import WebKit

/// Loads Discord login and extracts the user token for classic gateway RPC.
struct DiscordLoginWebView: View {
    var onToken: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DiscordLoginWebRepresentable(onToken: { token, username in
                onToken(token, username)
                dismiss()
            })
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Discord Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct DiscordLoginWebRepresentable: UIViewControllerRepresentable {
    var onToken: (String, String?) -> Void

    func makeUIViewController(context: Context) -> DiscordLoginController {
        DiscordLoginController(onToken: onToken)
    }

    func updateUIViewController(_ uiViewController: DiscordLoginController, context: Context) {}
}

final class DiscordLoginController: UIViewController {
    private let onToken: (String, String?) -> Void
    private var navigationDelegate: DiscordLoginNavigationDelegate?

    init(onToken: @escaping (String, String?) -> Void) {
        self.onToken = onToken
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let delegate = DiscordLoginNavigationDelegate(onToken: onToken)
        navigationDelegate = delegate

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = delegate
        webView.customUserAgent = [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)",
            "AppleWebKit/605.1.15 (KHTML, like Gecko)",
            "Version/17.4 Mobile/15E148 Safari/604.1"
        ].joined(separator: " ")
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let url = URL(string: "https://discord.com/login")!
        webView.load(URLRequest(url: url))
    }
}

private final class DiscordLoginNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onToken: (String, String?) -> Void
    private var didExtract = false
    private var pollTask: Task<Void, Never>?

    init(onToken: @escaping (String, String?) -> Void) {
        self.onToken = onToken
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let host = url.host ?? ""
        guard host.contains("discord.com") || host.contains("discordapp.com") else { return }

        // After login Discord redirects to /channels/@me or the app shell.
        let path = url.path
        let likelyLoggedIn = path.contains("/channels") || path.contains("/app") || path == "/"
        guard likelyLoggedIn || !path.contains("login") else { return }

        pollTask?.cancel()
        pollTask = Task { [weak self, weak webView] in
            for _ in 0..<20 {
                guard !Task.isCancelled, let self, let webView, !self.didExtract else { return }
                await self.attemptExtract(from: webView)
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }

    @MainActor
    private func attemptExtract(from webView: WKWebView) async {
        guard !didExtract else { return }
        let script = """
        (function() {
          function findToken() {
            try {
              var iframe = document.createElement('iframe');
              document.body.appendChild(iframe);
              var t = iframe.contentWindow.localStorage.token;
              iframe.remove();
              if (t) return t.replace(/"/g, '');
            } catch (e) {}
            try {
              if (window.localStorage && window.localStorage.token) {
                return String(window.localStorage.token).replace(/"/g, '');
              }
            } catch (e) {}
            try {
              var token = null;
              if (typeof webpackChunkdiscord_app !== 'undefined') {
                webpackChunkdiscord_app.push([
                  [Math.random()],
                  {},
                  function(req) {
                    for (var id in req.c) {
                      var m = req.c[id] && req.c[id].exports;
                      if (!m) continue;
                      if (m.default && typeof m.default.getToken === 'function') {
                        token = m.default.getToken();
                        break;
                      }
                      if (typeof m.getToken === 'function') {
                        token = m.getToken();
                        break;
                      }
                    }
                  }
                ]);
              }
              if (token) return String(token);
            } catch (e) {}
            return '';
          }
          function findUsername() {
            try {
              if (window.localStorage && window.localStorage.user_id_cache) {
                return null;
              }
            } catch (e) {}
            return null;
          }
          return JSON.stringify({ token: findToken() || '', username: findUsername() });
        })();
        """

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(script) { [weak self] result, error in
                defer { continuation.resume() }
                guard let self, !self.didExtract else { return }
                if let error {
                    Log.discord.debug("Discord token JS: \(error.localizedDescription)")
                    return
                }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = obj["token"] as? String,
                      token.count > 20 else {
                    return
                }
                self.didExtract = true
                let username = obj["username"] as? String
                Log.discord.info("Extracted Discord token from WebView")
                DispatchQueue.main.async {
                    self.onToken(token, username)
                }
            }
        }
    }
}

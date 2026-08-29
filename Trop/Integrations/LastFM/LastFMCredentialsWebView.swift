//
//  LastFMCredentialsWebView.swift
//  Trop
//

@preconcurrency import SwiftUI
import WebKit

/// Loads Last.fm's API account page and extracts API Key + Shared secret from the DOM.
struct LastFMCredentialsWebView: View {
    var onExtracted: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LastFMCredentialsWebRepresentable(onExtracted: { key, secret in
                onExtracted(key, secret)
                dismiss()
            })
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Last.fm API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct LastFMCredentialsWebRepresentable: UIViewControllerRepresentable {
    var onExtracted: (String, String) -> Void

    func makeUIViewController(context: Context) -> LastFMCredentialsController {
        LastFMCredentialsController(onExtracted: onExtracted)
    }

    func updateUIViewController(_ uiViewController: LastFMCredentialsController, context: Context) {}
}

final class LastFMCredentialsController: UIViewController {
    private let onExtracted: (String, String) -> Void
    private var navigationDelegate: LastFMCredentialsNavigationDelegate?

    init(onExtracted: @escaping (String, String) -> Void) {
        self.onExtracted = onExtracted
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let delegate = LastFMCredentialsNavigationDelegate(onExtracted: onExtracted)
        navigationDelegate = delegate

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = delegate
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let url = URL(string: "https://www.last.fm/api/account/create")!
        webView.load(URLRequest(url: url))
    }
}

private final class LastFMCredentialsNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onExtracted: (String, String) -> Void
    private var didExtract = false

    init(onExtracted: @escaping (String, String) -> Void) {
        self.onExtracted = onExtracted
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let host = webView.url?.host, host.contains("last.fm") else { return }
        guard !didExtract else { return }

        let script = """
        (function() {
          function pickHex(text) {
            var m = text.match(/[a-f0-9]{32}/i);
            return m ? m[0] : '';
          }
          var body = document.body ? document.body.innerText : '';
          var apiKey = '';
          var secret = '';
          var keyMatch = body.match(/API\\s*Key[\\s\\S]{0,80}?([a-f0-9]{32})/i);
          var secretMatch = body.match(/Shared\\s*secret[\\s\\S]{0,80}?([a-f0-9]{32})/i);
          if (keyMatch) apiKey = keyMatch[1];
          if (secretMatch) secret = secretMatch[1];
          if (!apiKey || !secret) {
            var codes = Array.from(document.querySelectorAll('code, pre, input, .api-key, .api_key'));
            var hexes = [];
            codes.forEach(function(el) {
              var v = (el.value || el.textContent || '').trim();
              var h = pickHex(v);
              if (h) hexes.push(h);
            });
            if (!apiKey && hexes.length > 0) apiKey = hexes[0];
            if (!secret && hexes.length > 1) secret = hexes[1];
          }
          return JSON.stringify({ apiKey: apiKey || '', secret: secret || '' });
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, !self.didExtract else { return }
            if let error {
                Log.lastfm.error("Last.fm credential JS failed: \(error.localizedDescription)")
                return
            }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let apiKey = obj["apiKey"], let secret = obj["secret"],
                  apiKey.count == 32, secret.count == 32 else {
                return
            }
            self.didExtract = true
            Log.lastfm.info("Extracted Last.fm API credentials from WebView")
            DispatchQueue.main.async {
                self.onExtracted(apiKey, secret)
            }
        }
    }
}

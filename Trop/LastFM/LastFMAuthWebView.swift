//
//  LastFMAuthWebView.swift
//  Trop
//

@preconcurrency import SwiftUI
import UIKit
import WebKit

/// Loads Last.fm desktop auth URL and completes when the user grants access.
struct LastFMAuthWebView: View {
    let authURL: URL
    let token: String
    var onComplete: (Result<LastFMAuthentication, Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LastFMAuthPresenter(
                authURL: authURL,
                token: token,
                onComplete: { result in
                    onComplete(result)
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Last.fm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct LastFMAuthPresenter: UIViewControllerRepresentable {
    typealias UIViewControllerType = LastFMAuthController

    let authURL: URL
    let token: String
    var onComplete: (Result<LastFMAuthentication, Error>) -> Void

    func makeUIViewController(
        context: UIViewControllerRepresentableContext<LastFMAuthPresenter>
    ) -> LastFMAuthController {
        LastFMAuthController(authURL: authURL, token: token, onComplete: onComplete)
    }

    func updateUIViewController(
        _ uiViewController: LastFMAuthController,
        context: UIViewControllerRepresentableContext<LastFMAuthPresenter>
    ) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {}
}

final class LastFMAuthController: UIViewController {
    private let authURL: URL
    private let token: String
    private let onComplete: (Result<LastFMAuthentication, Error>) -> Void
    private var navigationDelegate: LastFMAuthNavigationDelegate?

    init(
        authURL: URL,
        token: String,
        onComplete: @escaping (Result<LastFMAuthentication, Error>) -> Void
    ) {
        self.authURL = authURL
        self.token = token
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let delegate = LastFMAuthNavigationDelegate(token: token, onComplete: onComplete)
        navigationDelegate = delegate
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = delegate
        view = webView
        webView.load(URLRequest(url: authURL))
    }
}

private final class LastFMAuthNavigationDelegate: NSObject, WKNavigationDelegate {
    private let token: String
    private let onComplete: (Result<LastFMAuthentication, Error>) -> Void
    private var didFinish = false

    init(token: String, onComplete: @escaping (Result<LastFMAuthentication, Error>) -> Void) {
        self.token = token
        self.onComplete = onComplete
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let absolute = url.absoluteString.lowercased()
        // After granting, Last.fm lands on a success / settings / home page.
        let granted = absolute.contains("auth") && (
            absolute.contains("yes")
                || absolute.contains("success")
                || absolute.contains("granted")
                || url.path.contains("/api/auth") == false && absolute.contains("last.fm")
        )
        // Also detect the common "You've granted access" page body.
        let script = """
        (function() {
          var body = (document.body && document.body.innerText) || '';
          return /granted access|has been authorised|has been authorized|application is now authorised|application is now authorized/i.test(body);
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, !self.didFinish else { return }
            let bodyGranted = (result as? Bool) == true
            if bodyGranted || granted {
                self.completeSession()
            }
        }
    }

    private func completeSession() {
        guard !didFinish else { return }
        didFinish = true
        Task {
            do {
                let auth = try await LastFM.shared.getSession(token: token)
                await MainActor.run {
                    self.onComplete(.success(auth))
                }
            } catch {
                // User may still be on the grant page — allow another attempt.
                await MainActor.run {
                    self.didFinish = false
                }
                Log.lastfm.debug("getSession not ready yet: \(error.localizedDescription)")
            }
        }
    }
}

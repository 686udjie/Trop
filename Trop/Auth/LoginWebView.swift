//
//  LoginWebView.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

@preconcurrency import SwiftUI
import WebKit

// Presented as a sheet — launches Google OAuth in a full-screen WKWebView
struct LoginWebView: View {
    let model: LoginViewModel

    var body: some View {
        Presenter(model: model)
            .ignoresSafeArea()
    }
}

// Bridges the WKWebView into SwiftUI using a hosting controller
private struct Presenter: UIViewControllerRepresentable {
    typealias UIViewControllerType = WebLoginController

    let model: LoginViewModel

    func makeUIViewController(context: UIViewControllerRepresentableContext<Presenter>) -> WebLoginController {
        WebLoginController(model: model)
    }

    func updateUIViewController(_ vc: WebLoginController, context: UIViewControllerRepresentableContext<Presenter>) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {}
}

// Controller that hosts a WKWebView for the Google OAuth flow
final class WebLoginController: UIViewController {
    let model: LoginViewModel
    private var delegate: LoginNavigationDelegate?

    init(model: LoginViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let delegate = LoginNavigationDelegate(model: model)
        self.delegate = delegate

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = delegate
        view = webView

        let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com")!
        webView.load(URLRequest(url: url))
    }
}

// Handles navigation and extracts auth cookies on login redirect
private final class LoginNavigationDelegate: NSObject, WKNavigationDelegate {
    let model: LoginViewModel

    init(model: LoginViewModel) {
        self.model = model
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host?.contains("music.youtube.com") == true else {
            return
        }

        Log.login.debug("Redirected to \(url.host ?? "") — extracting cookies...")

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            var cookieDict: [String: String] = [:]
            var sapisid: String?
            var visitorData: String?

            Log.login.debug("Found \(cookies.count) total cookies")

            for cookie in cookies where cookie.domain.contains("youtube.com") || cookie.domain.contains("google.com") {
                cookieDict[cookie.name] = cookie.value
                Log.login.debug("  Cookie: \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")

                if cookie.name == "__Secure-3PSAPISID" || cookie.name == "SAPISID" {
                    sapisid = cookie.value
                    Log.login.debug("  ✅ Found SAPISID!")
                }

                if cookie.name == "visitor_data" {
                    visitorData = cookie.value
                    Log.login.debug("  ✅ Found visitor_data!")
                }
            }

            if sapisid == nil {
                Log.login.notice("  ❌ No SAPISID found — login may have failed")
            }

            self?.model.cookies = cookieDict
            self?.model.sapisid = sapisid
            self?.model.visitorData = visitorData
            self?.model.isLoggedIn = sapisid != nil
            self?.model.isPresented = false

            // Extract dataSyncId from the YouTube page config via JS injection
            webView.evaluateJavaScript("window.yt?.config_?.DATASYNC_ID ?? ''") { result, error in
                if let dataSyncId = result as? String, !dataSyncId.isEmpty {
                    self?.model.dataSyncId = dataSyncId
                    Log.login.debug("  ✅ Found dataSyncId: \(dataSyncId.prefix(15))...")
                } else if let error = error {
                    Log.login.error("  ⚠️ JS eval for dataSyncId failed: \(error.localizedDescription)")
                } else {
                    Log.login.notice("  ⚠️ dataSyncId not found in page context")
                }
            }
        }
    }
}

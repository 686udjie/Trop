//
// WebAuthentication.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation
import WebKit
import Combine

// Publishes the current WKWebView URL and extracted cookies
class WebAuthentication: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var url: URL?
    @Published var cookies: [String: String] = [:]

    private var webView: WKWebView?

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
    }

    func load(_ request: URLRequest) {
        webView?.load(request)
    }

    func extractCookies() {
        guard let webView = webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            var dict: [String: String] = [:]
            for cookie in cookies where cookie.domain.contains("youtube.com") || cookie.domain.contains("google.com") {
                dict[cookie.name] = cookie.value
            }
            DispatchQueue.main.async {
                self?.cookies = dict
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        url = webView.url
        extractCookies()
    }
}

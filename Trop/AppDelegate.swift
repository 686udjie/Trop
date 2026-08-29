//
//  AppDelegate.swift
//  Trop
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        bootstrapIntegrations()
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if DiscordAuth.handleRedirectURL(url) {
            return true
        }
        return false
    }

    private func bootstrapIntegrations() {
        let config = IntegrationsConfig.load()
        LastFM.initialize(apiKey: config.lastFMAPIKey, secret: config.lastFMAPISecret)
        LastFMScrobbler.shared.restoreSession()

        DiscordRpcManager.shared.initialize(clientId: config.discordClientID)
        if SettingsStore.shared.discordRPCEnabled {
            Task { await DiscordRpcManager.shared.connectIfAuthorized() }
        }
    }
}

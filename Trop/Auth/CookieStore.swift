//
//  CookieStore.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// High-level session wrapper — delegates persistence to KeychainStorage
actor CookieStore {
  private let keychain: KeychainStorage

  init(keychain: KeychainStorage = KeychainStorage()) {
    self.keychain = keychain
  }

    func cookies() async -> [String: String] {
        guard let state = await state(), let cookie = state.cookie, !cookie.isEmpty else { return [:] }
        return parseCookieString(cookie)
    }

    func sapisid() async -> String? {
        await state()?.sapisidHash
    }

    func visitorData() async -> String? {
        await state()?.visitorData
    }

    func dataSyncId() async -> String? {
        await state()?.dataSyncId
    }

    func isLoggedIn() async -> Bool {
        await state()?.isLoggedIn ?? false
    }

    private func state() async -> SessionState? {
        try? await keychain.loadSessionState()
    }

    func save(cookies: [String: String], sapisid: String?, visitorData: String?, dataSyncId: String? = nil) {
        let cookieString = cookies
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
        let state = SessionState(
            cookie: cookieString.isEmpty ? nil : cookieString,
            sapisidHash: sapisid,
            visitorData: visitorData,
            dataSyncId: dataSyncId,
            locale: .default
        )
        try? keychain.save(state, for: KeychainStorage.sessionKey)
    }

    func clear() {
        try? keychain.clear()
    }

  private func parseCookieString(_ cookieString: String) -> [String: String] {
    var result: [String: String] = [:]
    let pairs = cookieString.split(separator: ";")
    for pair in pairs {
      let trimmed = pair.trimmingCharacters(in: .whitespaces)
      let parts = trimmed.split(separator: "=", maxSplits: 1)
      if parts.count == 2 {
        result[String(parts[0])] = String(parts[1])
      }
    }
    return result
  }
}

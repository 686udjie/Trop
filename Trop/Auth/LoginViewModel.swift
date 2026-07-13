//
//  LoginViewModel.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation
import Combine

// Drives sign-in and session verification, owns the CookieStore + InnerTube coordination
    @MainActor
    final class LoginViewModel: ObservableObject {
        @Published var cookies: [String: String] = [:]
        @Published var sapisid: String?
        @Published var visitorData: String?
        @Published var dataSyncId: String?
        @Published var isLoggedIn = false
        @Published var isPresented = false

        private let authService = AuthService.shared
        private let cookieStore = CookieStore()
        private var loadTask: Task<Void, Never>?

        func handleLogin(cookies: [String: String], sapisid: String?, visitorData: String?, dataSyncId: String? = nil) {
            self.cookies = cookies
            self.sapisid = sapisid
            self.visitorData = visitorData
            self.dataSyncId = dataSyncId

            loadTask?.cancel()
            loadTask = Task { [weak self] in
                guard let self else { return }
        do {
            try await self.authService.importSession(from: self.cookieString(from: cookies), dataSyncId: dataSyncId)
            self.isLoggedIn = true
            self.isPresented = false
        } catch {
            print("[LoginViewModel] importSession failed: \(error)")
        }
            }
        }

        func logout() {
            Task { [weak self] in
                guard let self else { return }
                await self.authService.logout()
                self.cookies = [:]
                self.sapisid = nil
                self.visitorData = nil
                self.dataSyncId = nil
                self.isLoggedIn = false
            }
        }

        func restoreSessionIfPresent() {
            loadTask?.cancel()
            loadTask = Task { [weak self] in
                guard let self else { return }
                let loggedIn = await self.cookieStore.isLoggedIn()
                guard loggedIn else { return }

                self.cookies = await self.cookieStore.cookies()
                self.sapisid = await self.cookieStore.sapisid()
                self.visitorData = await self.cookieStore.visitorData()
                self.dataSyncId = await self.cookieStore.dataSyncId()
                self.isLoggedIn = true
            }
        }

        private func cookieString(from dict: [String: String]) -> String {
            dict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }
    }

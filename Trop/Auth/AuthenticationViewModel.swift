//
// AuthenticationViewModel.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation
import Combine

// Holds the result of a session verification probe against account/account_menu
enum AuthenticationResult {
    case notStarted
    case loading
    case success(String) // account display name
    case failure(Error?, String)
}

extension AuthenticationResult {
    var isVerified: Bool {
        if case .success = self {
            true
        } else {
            false
        }
    }

    var isRefreshing: Bool {
        if case .loading = self {
            true
        } else {
            false
        }
    }
}

// Drives the sign-in / verification UI — wraps AuthService and updates @Published state
class AuthenticationViewModel: ObservableObject {
    @Published var authenticationResult: AuthenticationResult = .notStarted
    @Published var isVerifying = false
    @Published var webAuthentication: WebAuthentication?

    private let authService = AuthService.shared
    private var verifyTask: Task<Void, Never>?

    func verifyAuthentication() async {
        cancelPendingVerify()
        await MainActor.run {
            isVerifying = true
            authenticationResult = .loading
        }

        do {
            let ok = try await authService.verifyLogin()
            await MainActor.run {
                if ok {
                    authenticationResult = .success("Authenticated")
                } else {
                    authenticationResult = .failure(nil, "Account menu did not contain an account name.")
                }
                isVerifying = false
            }
        } catch {
            await MainActor.run {
                authenticationResult = .failure(error, error.localizedDescription)
                isVerifying = false
            }
        }
    }

    func cancel() {
        verifyTask?.cancel()
        verifyTask = nil

        Task { @MainActor in
            isVerifying = false
            if case .loading = authenticationResult {
                authenticationResult = .notStarted
            }
        }
    }

    func reset() {
        cancel()
        Task { @MainActor in
            authenticationResult = .notStarted
            webAuthentication = nil
        }
        Task { await authService.logout() }
    }

    private func cancelPendingVerify() {
        verifyTask?.cancel()
    }
}

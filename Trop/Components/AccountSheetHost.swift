//
//  AccountSheetHost.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI

/// Account sheet state shared by the Library and Explore tabs (the Home tab
/// drives the same sheets through its view model instead).
@MainActor
@Observable
final class AccountSheetState {
    var accountName = "Guest"
    var accountImageUrl: String?
    var isLoginSheetPresented = false
    var isAccountSheetPresented = false
    let loginModel = LoginViewModel()

    var isLoggedIn: Bool { loginModel.isLoggedIn }

    func restoreSession() {
        loginModel.restoreSessionIfPresent()
    }

    func fetchAccountInfo() async {
        guard loginModel.isLoggedIn else { return }
        do {
            let info = try await InnerTube.shared.accountInfo()
            accountName = info.name
            accountImageUrl = info.thumbnailUrl
        } catch {
            Log.loginViewModel.error("Failed to fetch account info: \(error)")
        }
    }

    func handleLoginChange(_ loggedIn: Bool) {
        if loggedIn {
            isLoginSheetPresented = false
            Task { await fetchAccountInfo() }
        }
    }

    func signOut() {
        loginModel.logout()
        accountName = "Guest"
        accountImageUrl = nil
        isAccountSheetPresented = false
    }
}

/// Attaches the login + account sheets and their wiring. `onSettings` pushes
/// the settings route on the caller's tab path.
struct AccountSheetHost: ViewModifier {
    @Bindable var state: AccountSheetState
    var onSettings: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $state.isLoginSheetPresented) {
                NavigationStack {
                    LoginWebView(model: state.loginModel)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { state.isLoginSheetPresented = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $state.isAccountSheetPresented) {
                AccountSheetView(
                    isLoggedIn: state.isLoggedIn,
                    titleText: state.accountName,
                    accountImageUrl: state.accountImageUrl,
                    onDone: { state.isAccountSheetPresented = false },
                    onLogin: {
                        state.isAccountSheetPresented = false
                        DispatchQueue.main.async {
                            state.isLoginSheetPresented = true
                        }
                    },
                    onSettings: {
                        state.isAccountSheetPresented = false
                        onSettings()
                    },
                    onSignOut: { state.signOut() }
                )
            }
            .onChange(of: state.loginModel.isLoggedIn) { _, loggedIn in
                state.handleLoginChange(loggedIn)
            }
    }
}

extension View {
    func accountSheets(state: AccountSheetState, onSettings: @escaping () -> Void) -> some View {
        modifier(AccountSheetHost(state: state, onSettings: onSettings))
    }
}

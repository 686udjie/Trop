//
//  LoginViewModel.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation
import Combine

// Manages login state and publishes results to SwiftUI
class LoginViewModel: ObservableObject {
    @Published var cookies: [String: String] = [:]
    @Published var sapisid: String?
    @Published var visitorData: String?
    @Published var isLoggedIn = false
    @Published var isPresented = false
}

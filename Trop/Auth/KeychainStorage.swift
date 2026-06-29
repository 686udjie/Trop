//
// KeychainStorage.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation
import Security

// Wraps iOS Security framework for encrypted Codable persistence
actor KeychainStorage {
  static let serviceName = "com.trop.app"
  static let sessionKey = "sessionState"

  private let service: String
  private let keychainQuery: [String: Any]

  init(serviceName: String = KeychainStorage.serviceName) {
    self.service = serviceName
    self.keychainQuery = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: KeychainStorage.sessionKey
    ]
  }

  nonisolated func loadSessionState() async throws -> SessionState {
    try await loadSessionStateInternal(
      keychainQuery: [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: KeychainStorage.serviceName,
        kSecAttrAccount as String: KeychainStorage.sessionKey
      ],
      key: KeychainStorage.sessionKey
    )
  }

  private nonisolated func loadSessionStateInternal(
    keychainQuery: [String: Any],
    key: String
  ) async throws -> SessionState {
    var query = keychainQuery
    query[kSecAttrAccount as String] = key
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status != errSecItemNotFound else {
      throw KeychainError.itemNotFound
    }
    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status)
    }
    guard let data = result as? Data else {
      throw KeychainError.invalidData
    }
    return try JSONDecoder().decode(SessionState.self, from: data)
  }

  // Saves a Codable value to Keychain, replacing any existing entry for the key
  nonisolated func save<T: Codable>(_ value: T, for key: String) throws {
    let data = try JSONEncoder().encode(value)
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: KeychainStorage.serviceName,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(query as CFDictionary)

    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let status = SecItemAdd(query as CFDictionary, nil)
    if status != errSecSuccess {
      throw KeychainError.unhandledError(status)
    }
  }

  // Loads and decodes a Codable value from Keychain by key — caller must know the expected type
  func load<T: Codable>(for key: String) throws -> T {
    var query = keychainQuery
    query[kSecAttrAccount as String] = key
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status != errSecItemNotFound else {
      throw KeychainError.itemNotFound
    }

    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status)
    }

    guard let data = result as? Data else {
      throw KeychainError.invalidData
    }

    return try JSONDecoder().decode(T.self, from: data)
  }

  // Removes a single item from Keychain by key
  nonisolated func delete(for key: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: KeychainStorage.serviceName,
      kSecAttrAccount as String: key
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw KeychainError.unhandledError(status)
    }
  }

  // Removes all stored session data from Keychain
  nonisolated func clear() throws {
    try delete(for: KeychainStorage.sessionKey)
  }
}

// Errors that can occur during Keychain operations
enum KeychainError: Error, LocalizedError {
  case itemNotFound
  case invalidData
  case unhandledError(OSStatus)

  var errorDescription: String? {
    switch self {
    case .itemNotFound:
      return "Item not found in Keychain"
    case .invalidData:
      return "Invalid data format in Keychain"
    case .unhandledError(let status):
      return "Keychain error: OSStatus \(status)"
    }
  }
}
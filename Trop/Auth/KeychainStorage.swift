//
// KeychainStorage.swift
// Trop
//
// Created by 686udjie on 29/06/2026.
//

import Foundation

// Wraps iOS Security framework for encrypted Codable persistence
actor KeychainStorage {
  static let serviceName = "com.trop.app"
  static let sessionKey = "sessionState"

  private let store: SecureStore

  init(serviceName: String = KeychainStorage.serviceName) {
    self.store = SecureStore(service: serviceName)
  }

  nonisolated func loadSessionState() async throws -> SessionState {
    try loadDataDecoded(for: KeychainStorage.sessionKey)
  }

  // Saves a Codable value to Keychain, replacing any existing entry for the key
  nonisolated func save<T: Codable>(_ value: T, for key: String) throws {
    try store.save(try JSONEncoder().encode(value), for: key)
  }

  // Loads and decodes a Codable value from Keychain by key — caller must know the expected type
  func load<T: Codable>(for key: String) throws -> T {
    try loadDataDecoded(for: key)
  }

  private nonisolated func loadDataDecoded<T: Codable>(for key: String) throws -> T {
    let data: Data
    do {
      data = try store.load(for: key)
    } catch {
      throw Self.map(error)
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw KeychainError.invalidData
    }
  }

  // Removes a single item from Keychain by key
  nonisolated func delete(for key: String) throws {
    do {
      try store.delete(for: key)
    } catch {
      throw Self.map(error)
    }
  }

  // Removes all stored session data from Keychain
  nonisolated func clear() throws {
    try delete(for: KeychainStorage.sessionKey)
  }

  private static func map(_ error: Error) -> KeychainError {
    switch error as? SecureStoreError {
    case .notFound:
      return .itemNotFound
    case .unhandled(let status):
      return .unhandledError(status)
    case nil:
      return .unhandledError(errSecInternalError)
    }
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

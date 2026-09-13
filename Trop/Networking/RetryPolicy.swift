//
//  RetryPolicy.swift
//  Trop
//
// Created by 686udjie on 13/09/2026.
//

import Foundation

/// Exponential backoff with jitter, extracted from InnerTube's retry loop
/// for reuse. Attempt indexing is 0-based: the first retry waits
/// `baseDelay`, doubling (capped at `maxDelay`) plus uniform jitter after.
struct RetryPolicy: Sendable {
    var maxAttempts: Int
    var baseDelay: Duration
    var factor: Double
    var maxDelay: Duration
    var jitter: Duration

    static let innerTube = RetryPolicy(
        maxAttempts: 3,
        baseDelay: .milliseconds(500),
        factor: 2,
        maxDelay: .seconds(30),
        jitter: .milliseconds(200)
    )

    func delay(for attempt: Int) -> Duration {
        let exponential = baseDelay * pow(factor, Double(max(attempt, 0)))
        let capped = min(exponential, maxDelay)
        return capped + .milliseconds(Int.random(in: 0...jitterMilliseconds))
    }

    func run<T>(
        _ operation: () async throws -> T,
        isRetryable: (Error) -> Bool,
        onRetry: ((Int, Error) -> Void)? = nil
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts - 1, isRetryable(error) else { break }
                onRetry?(attempt, error)
                try? await Task.sleep(for: delay(for: attempt))
            }
        }
        throw lastError ?? RetryError.exhausted
    }

    private var jitterMilliseconds: Int {
        let parts = jitter.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}

enum RetryError: Error {
    /// The policy allowed zero attempts, so nothing ran.
    case exhausted
}

//
//  LoggedTask.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import Foundation

/// Runs an async throwing operation in a `Task`, logging any error instead of
/// letting it go silent. Replaces the repeated
/// `Task { do { try await … } catch { Log.x.error("…") } }` boilerplate.
///
/// Bodies that only `await` (never throw) work too — non-throwing closures
/// are accepted wherever a throwing one is expected.
@MainActor
func loggedTask(
    _ logger: AppLogger,
    _ message: String,
    operation: @escaping @MainActor @Sendable () async throws -> Void
) {
    Task { @MainActor in
        do {
            try await operation()
        } catch {
            logger.error("\(message): \(error)")
        }
    }
}

//
//  HttpClient.swift
//  Trop
//
// Created by 686udjie on 13/09/2026.
//

import Foundation

/// Shared URLSession boilerplate: perform a request and get back data plus a
/// validated HTTP response, without each service re-typing the `data(for:)` +
/// `as? HTTPURLResponse` + status-range dance. Callers keep their
/// domain-specific error mapping on top; network errors propagate untouched.
enum HttpClient {
    /// Performs `request`, throwing `HttpError.notHTTPResponse` when the
    /// response isn't HTTP. Does NOT validate the status code.
    static func data(
        for request: URLRequest,
        session: URLSession = .shared
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HttpError.notHTTPResponse
        }
        return (data, http)
    }

    /// Performs a GET for `url`. See `data(for:)`.
    static func data(
        from url: URL,
        session: URLSession = .shared
    ) async throws -> (Data, HTTPURLResponse) {
        try await data(for: URLRequest(url: url), session: session)
    }

    /// Like `data(for:)` but additionally throws `HttpError.status(code, data)`
    /// for non-2xx responses.
    static func validatedData(
        for request: URLRequest,
        session: URLSession = .shared
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, http) = try await data(for: request, session: session)
        guard (200...299).contains(http.statusCode) else {
            throw HttpError.status(http.statusCode, data)
        }
        return (data, http)
    }
}

enum HttpError: Error {
    case notHTTPResponse
    case status(Int, Data)
}

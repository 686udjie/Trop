//
//  LastFMModels.swift
//  Trop
//

import Foundation

struct LastFMTokenResponse: Decodable {
    let token: String
}

struct LastFMAuthentication: Decodable {
    let session: Session

    struct Session: Decodable {
        let name: String
        let key: String
        let subscriber: Int?
    }
}

struct LastFMAPIErrorBody: Decodable {
    let error: Int
    let message: String
}

enum LastFMError: Error, LocalizedError {
    case notConfigured
    case notLoggedIn
    case api(code: Int, message: String)
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Last.fm API credentials are not configured"
        case .notLoggedIn:
            return "Not logged in to Last.fm"
        case .api(_, let message):
            return message
        case .invalidResponse:
            return "Invalid response from Last.fm"
        case .network(let error):
            return error.localizedDescription
        }
    }
}

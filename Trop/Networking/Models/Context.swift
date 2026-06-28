//
//  Context.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Request context sent with every InnerTube API call
struct Context: Codable {
    let client: Client
    let user: User?
    let request: RequestConfig?

    struct Client: Codable {
        let clientName: String
        let clientVersion: String
        let gl: String
        let hl: String
        let visitorData: String?
    }

    struct User: Codable {
        let onBehalfOfUser: String?
    }

    struct RequestConfig: Codable {
        let useSsl: Bool
    }

    static func `default`(
        client: YouTubeClient,
        locale: YouTubeLocale = .default,
        visitorData: String? = nil
    ) -> Context {
        Context(
            client: Client(
                clientName: client.clientName,
                clientVersion: client.clientVersion,
                gl: locale.gl,
                hl: locale.hl,
                visitorData: visitorData
            ),
            user: nil,
            request: RequestConfig(useSsl: true)
        )
    }
}

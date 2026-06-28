//
//  RequestBuilder.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Builds URLRequest objects for InnerTube API calls with all required headers
enum RequestBuilder {
    private static let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!

    static func buildRequest(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient,
        visitorData: String?,
        cookies: [String: String],
        sapisid: String?
    ) -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("\(client.clientId)", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "X-Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")

        if let visitorData = visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        // Only send auth headers for clients that support login (matching Metrolist's ytClient)
        if client.loginSupported {
            // Attach auth cookies as a single Cookie header
            if !cookies.isEmpty {
                let cookieString = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
                request.setValue(cookieString, forHTTPHeaderField: "Cookie")
            }

            // Generate SAPISID hash for signed-in Authorization header
            if let sapisid = sapisid {
                request.setValue(
                    SAPISIDAuth.authorizationHeader(sapisid: sapisid),
                    forHTTPHeaderField: "Authorization"
                )
            }
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return request
    }
}

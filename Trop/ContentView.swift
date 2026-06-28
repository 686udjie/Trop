//
//  ContentView.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var resultText = ""

    var body: some View {
        // Simple test UI — button triggers a /browse API call
        VStack(spacing: 16) {
            ScrollView {
                Text(resultText)
                    .font(.system(.caption, design: .monospaced))
            }
            Button("Test /browse") {
                Task {
                    await testBrowse()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // Calls InnerTube /browse and displays the response
    private func testBrowse() async {
        resultText = "Calling /browse..."
        do {
            let json = try await InnerTube.shared.browse(
                browseId: "FEmusic_home"
            )
            if let responseContext = json["responseContext"] {
                resultText = "SUCCESS\n\nresponseContext: \(responseContext)\n\nFull keys: \(json.keys.sorted())"
            } else {
                resultText = "Unexpected response:\n\(json)"
            }
        } catch {
            resultText = "Error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}

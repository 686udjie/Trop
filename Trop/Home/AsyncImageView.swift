//
//  AsyncImageView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct AsyncImageView: View {
    let url: String?
    var placeholder: Image?

    var body: some View {
        if let urlString = url, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        (placeholder ?? Image(systemName: "music.note"))
            .resizable()
            .scaledToFit()
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
    }
}

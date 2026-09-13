//
//  Share.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import UIKit

/// Presents a `UIActivityViewController` from the key window. Consolidates
/// the copy-pasted window lookup in SongMenuSheet and PlaylistMoreSheet.
/// Pass `afterDismiss` when the sheet must close first (presentation is then
/// deferred slightly so the dismiss animation wins the window).
@MainActor
func presentShareSheet(items: [Any], afterDismiss dismiss: (() -> Void)? = nil) {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          let window = scene.windows.first(where: { $0.isKeyWindow }),
          let root = window.rootViewController else { return }
    let present = {
        root.present(
            UIActivityViewController(activityItems: items, applicationActivities: nil),
            animated: true
        )
    }
    if let dismiss {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: present)
    } else {
        present()
    }
}

extension URL {
    static func songShareURL(videoId: String) -> URL? {
        URL(string: "https://music.youtube.com/watch?v=\(videoId)")
    }

    static func playlistShareURL(id: String) -> URL? {
        URL(string: "https://music.youtube.com/playlist?list=\(id)")
    }
}

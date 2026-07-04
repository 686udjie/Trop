//
//  YouTubeGridItemView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct YouTubeGridItemView: View {
    var item: YTItem
    var onTap: () -> Void

    @State private var resolvedDuration: Int = 0
    private let artworkSize: CGFloat = 160

    private var videoId: String? {
        switch item {
        case .song(let s): return s.videoId
        case .episode(let e): return e.videoId
        default: return nil
        }
    }

    private var subtitleText: String {
        switch item {
        case .song(let s):
            let artistStr = s.artists.map(\.name).joined(separator: ", ")
            let effectiveDuration = s.duration > 0 ? s.duration : resolvedDuration
            let durationStr = effectiveDuration.formattedDuration
            let result: String
            if artistStr.isEmpty { result = durationStr }
            else if durationStr.isEmpty { result = artistStr }
            else { result = "\(artistStr) • \(durationStr)" }
            return result
        case .episode(let e):
            let artistStr = e.artists.map(\.name).joined(separator: ", ")
            let effectiveDuration = e.duration > 0 ? e.duration : resolvedDuration
            let durationStr = effectiveDuration.formattedDuration
            if artistStr.isEmpty { return durationStr }
            if durationStr.isEmpty { return artistStr }
            return "\(artistStr) • \(durationStr)"
        case .album(let a):
            let names = a.artists.map(\.name)
            return names.isEmpty ? "" : names.joined(separator: ", ")
        default:
            return ""
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImageView(url: item.thumbnailUrl)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: artworkSize, height: 220, alignment: .top)
        }
        .buttonStyle(.plain)
        .task { await resolveDuration() }
        .onReceive(NotificationCenter.default.publisher(for: .durationDidUpdate)) { notification in
            guard let vid = notification.userInfo?["videoId"] as? String, vid == videoId else { return }
            resolvedDuration = DurationCache.get(vid) ?? 0
        }
    }

    private func resolveDuration() async {
        guard let vid = videoId else { return }
        switch item {
        case .song(let s) where s.duration > 0:
            resolvedDuration = s.duration
            return
        case .episode(let e) where e.duration > 0:
            resolvedDuration = e.duration
            return
        default: break
        }
        if let cached = DurationCache.get(vid), cached > 0 {
            resolvedDuration = cached
            return
        }
        guard !DurationCache.isPending(vid) else { return }
        DurationCache.markPending(vid)
        do {
            let duration = try await InnerTube.shared.fetchDuration(videoId: vid)
            resolvedDuration = duration
        } catch {
            DurationCache.clearPending(vid)
        }
    }
}

struct YouTubeListItemView: View {
    var item: YTItem
    var onTap: () -> Void

    @State private var resolvedDuration: Int = 0

    private var videoId: String? {
        switch item {
        case .song(let s): return s.videoId
        case .episode(let e): return e.videoId
        default: return nil
        }
    }

    private var subtitleText: String {
        switch item {
        case .song(let s):
            let artistStr = s.artists.map(\.name).joined(separator: ", ")
            let effectiveDuration = s.duration > 0 ? s.duration : resolvedDuration
            let durationStr = effectiveDuration.formattedDuration
            if artistStr.isEmpty { return durationStr }
            if durationStr.isEmpty { return artistStr }
            return "\(artistStr) • \(durationStr)"
        case .episode(let e):
            let artistStr = e.artists.map(\.name).joined(separator: ", ")
            let effectiveDuration = e.duration > 0 ? e.duration : resolvedDuration
            let durationStr = effectiveDuration.formattedDuration
            if artistStr.isEmpty { return durationStr }
            if durationStr.isEmpty { return artistStr }
            return "\(artistStr) • \(durationStr)"
        case .album(let a):
            return a.artists.map(\.name).joined(separator: ", ")
        default:
            return ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: item.thumbnailUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.blue)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .task { await resolveDuration() }
        .onReceive(NotificationCenter.default.publisher(for: .durationDidUpdate)) { notification in
            guard let vid = notification.userInfo?["videoId"] as? String, vid == videoId else { return }
            resolvedDuration = DurationCache.get(vid) ?? 0
        }
    }

    private func resolveDuration() async {
        guard let vid = videoId else { return }
        switch item {
        case .song(let s) where s.duration > 0:
            resolvedDuration = s.duration
            return
        case .episode(let e) where e.duration > 0:
            resolvedDuration = e.duration
            return
        default: break
        }
        if let cached = DurationCache.get(vid), cached > 0 {
            resolvedDuration = cached
            return
        }
        guard !DurationCache.isPending(vid) else { return }
        DurationCache.markPending(vid)
        do {
            let duration = try await InnerTube.shared.fetchDuration(videoId: vid)
            resolvedDuration = duration
        } catch {
            DurationCache.clearPending(vid)
        }
    }
}

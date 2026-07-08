//
//  PodcastDetailView.swift
//  Trop
//
//  Created by 686udjie on 06/07/2026.
//

import SwiftUI

// MARK: - View Model

@MainActor
@Observable
final class PodcastDetailViewModel {
    let browseId: String
    var podcast: PodcastDetailInfo?
    var isLoading = true
    var error: Error?

    private let innerTube = InnerTube.shared

    init(browseId: String) {
        self.browseId = browseId
    }

    func load() async {
        isLoading = true
        error = nil

        do {
            let json = try await innerTube.browse(browseId: browseId)
            let parsed = Self.parsePodcastDetail(from: json, browseId: browseId)
            print("[PodcastDetail] title=\(parsed.title) author=\(parsed.author ?? "nil") episodes=\(parsed.episodes.count)")
            podcast = parsed
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Parser

extension PodcastDetailViewModel {
    static func parsePodcastDetail(from json: [String: Any], browseId: String) -> PodcastDetailInfo {
        var title = "Unknown Podcast"
        var author: String?
        var descriptionText: String?
        var thumbnailUrl: String?
        var episodes: [EpisodeItem] = []

        let contents = json["contents"] as? [String: Any]
        let singleColumn = contents?["singleColumnBrowseResultsRenderer"] as? [String: Any]
        let twoColumn = contents?["twoColumnBrowseResultsRenderer"] as? [String: Any]

        let tabsArray: [[String: Any]]? = {
            if let tabs = twoColumn?["tabs"] as? [[String: Any]] { return tabs }
            if let tabs = singleColumn?["tabs"] as? [[String: Any]] { return tabs }
            return nil
        }()
        let firstTabSectionInner = tabsArray?
            .first
            .flatMap { $0["tabRenderer"] as? [String: Any] }
            .flatMap { $0["content"] as? [String: Any] }
            .flatMap { $0["sectionListRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }
        let firstTabSection = firstTabSectionInner
            .flatMap { $0["itemSectionRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }
            ?? firstTabSectionInner

        // --- Header ---
        let headerRenderer: [String: Any]? =
            firstTabSection?["musicResponsiveHeaderRenderer"] as? [String: Any]
            ?? (json["header"] as? [String: Any]).flatMap {
                $0["musicDetailHeaderRenderer"] as? [String: Any]
                ?? $0["musicResponsiveHeaderRenderer"] as? [String: Any]
            }

        if let header = headerRenderer {
            title = DetailParser.extractRunsText(header["title"] as? [String: Any]) ?? title
            thumbnailUrl = DetailParser.extractMusicThumbnail(header)

            descriptionText = header["description"]
                .flatMap { $0 as? [String: Any] }
                .flatMap { DetailParser.extractRunsText($0) }

            if let strapline = header["straplineTextOne"] as? [String: Any],
               let runs = strapline["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String {
                author = text
            }

            if author == nil,
               let subtitle = header["subtitle"] as? [String: Any],
               let runs = subtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed != "•" {
                        author = trimmed
                        break
                    }
                }
            }
        }

        // --- Episodes ---
        // Podcast episodes use musicMultiRowListItemRenderer inside
        // secondaryContents.sectionListRenderer.contents[].musicShelfRenderer.contents
        // or musicPlaylistShelfRenderer.contents

        func parseMultiRowEpisode(_ renderer: [String: Any]) -> EpisodeItem? {
            guard let onTap = renderer["onTap"] as? [String: Any],
                  let watch = onTap["watchEndpoint"] as? [String: Any],
                  let videoId = watch["videoId"] as? String else { return nil }

            let title = DetailParser.extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"

            let thumbnailUrl: String? = {
                if let thumbRenderer = renderer["thumbnail"] as? [String: Any],
                   let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                   let thumb = musicThumb["thumbnail"] as? [String: Any],
                   let thumbnails = thumb["thumbnails"] as? [[String: Any]],
                   let last = thumbnails.last,
                   let url = last["url"] as? String {
                    return url
                }
                return nil
            }()

            var duration = 0
            var publishDate: String?
            if let subtitle = renderer["subtitle"] as? [String: Any],
               let runs = subtitle["runs"] as? [[String: Any]] {
                let texts = runs.compactMap { $0["text"] as? String }
                // Subtitle format: "Date • Duration" or "Date"
                let separated = texts.filter { $0.trimmingCharacters(in: .whitespaces) != "•" }
                for text in separated {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains(":") {
                        duration = DetailParser.parseDuration(trimmed)
                    } else if publishDate == nil && !trimmed.isEmpty {
                        publishDate = trimmed
                    }
                }
            }

            return EpisodeItem(
                videoId: videoId,
                title: title,
                artists: [],
                duration: duration,
                thumbnailUrl: thumbnailUrl,
                publishDate: publishDate
            )
        }

        func parseContentItems(_ contentItems: [[String: Any]]) -> [EpisodeItem] {
            var result: [EpisodeItem] = []
            for item in contentItems {
                if let multiRow = item["musicMultiRowListItemRenderer"] as? [String: Any],
                   let episode = parseMultiRowEpisode(multiRow) {
                    result.append(episode)
                } else if let responsive = item["musicResponsiveListItemRenderer"] as? [String: Any],
                          let episode = EpisodeItem.from(responsive) {
                    result.append(episode)
                }
            }
            return result
        }

        func parseShelfContents(_ shelfDict: [String: Any]) -> [EpisodeItem] {
            if let shelf = shelfDict["musicShelfRenderer"] as? [String: Any],
               let contents = shelf["contents"] as? [[String: Any]] {
                return parseContentItems(contents)
            }
            if let shelf = shelfDict["musicPlaylistShelfRenderer"] as? [String: Any],
               let contents = shelf["contents"] as? [[String: Any]] {
                return parseContentItems(contents)
            }
            return []
        }

        // Primary: twoColumnBrowseResultsRenderer.secondaryContents
        if let twoCol = twoColumn,
           let secondary = twoCol["secondaryContents"] as? [String: Any],
           let sectionList = secondary["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionList["contents"] as? [[String: Any]] {
            for section in sectionContents {
                if let isr = section["itemSectionRenderer"] as? [String: Any],
                   let innerContents = isr["contents"] as? [[String: Any]] {
                    for inner in innerContents {
                        episodes += parseShelfContents(inner)
                    }
                } else {
                    episodes += parseShelfContents(section)
                }
            }
        }

        // Fallback: singleColumnBrowseResultsRenderer
        if episodes.isEmpty,
           let singleCol = singleColumn,
           let tabs = singleCol["tabs"] as? [[String: Any]],
           let sections = tabs.first
            .flatMap({ $0["tabRenderer"] as? [String: Any] })
            .flatMap({ $0["content"] as? [String: Any] })
            .flatMap({ $0["sectionListRenderer"] as? [String: Any] })
            .flatMap({ $0["contents"] as? [[String: Any]] }) {
            for section in sections {
                if let isr = section["itemSectionRenderer"] as? [String: Any],
                   let innerContents = isr["contents"] as? [[String: Any]] {
                    for inner in innerContents {
                        episodes += parseShelfContents(inner)
                    }
                } else {
                    episodes += parseShelfContents(section)
                }
            }
        }

        return PodcastDetailInfo(
            title: title,
            author: author,
            descriptionText: descriptionText,
            thumbnailUrl: thumbnailUrl,
            browseId: browseId,
            episodes: episodes
        )
    }
}

// MARK: - View

struct PodcastDetailView: View {
    let browseId: String
    @State private var viewModel: PodcastDetailViewModel

    @Environment(\.dismiss) private var dismiss

    init(browseId: String) {
        self.browseId = browseId
        _viewModel = State(initialValue: PodcastDetailViewModel(browseId: browseId))
    }

    var body: some View {
        ScrollView {
            Group {
                if viewModel.isLoading {
                    loadingView
                        .containerRelativeFrame(.vertical)
                } else if let error = viewModel.error {
                    ContentUnavailableView(
                        "Couldn't load podcast",
                        systemImage: "exclamationmark.circle",
                        description: Text(error.localizedDescription)
                    )
                    .containerRelativeFrame(.vertical)
                } else if let podcast = viewModel.podcast {
                    podcastContent(for: podcast)
                } else {
                    ContentUnavailableView(
                        "No podcast data",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Could not parse podcast details")
                    )
                    .containerRelativeFrame(.vertical)
                }
            }
        }
        .scrollDisabled(viewModel.isLoading || viewModel.error != nil || viewModel.podcast == nil)
        .navigationTitle(viewModel.podcast?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.isLoading else { return }
            await viewModel.load()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Loading podcast...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func podcastContent(for podcast: PodcastDetailInfo) -> some View {
        LazyVStack(spacing: 0) {
            header(for: podcast)
                .padding(.bottom, 8)

            if podcast.episodes.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Text("No episodes found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                episodeList(for: podcast)
            }
        }
    }

    @ViewBuilder
    private func header(for podcast: PodcastDetailInfo) -> some View {
        VStack(spacing: 12) {
            AsyncImageView(url: podcast.thumbnailUrl)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)

            Text(podcast.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let author = podcast.author {
                Text(author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !podcast.episodes.isEmpty {
                Text("\(podcast.episodes.count) episode\(podcast.episodes.count != 1 ? "s" : "")")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            if let desc = podcast.descriptionText, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
            }

            HStack(spacing: 20) {
                Button(action: { playAll(podcast) }) {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func episodeList(for podcast: PodcastDetailInfo) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(podcast.episodes.enumerated()), id: \.offset) { index, episode in
                Button(action: { playEpisode(episode, in: podcast) }) {
                    HStack(spacing: 12) {
                        AsyncImageView(url: episode.thumbnailUrl)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            let durationStr = episode.duration.formattedDuration
                            let subtitleText = durationStr.isEmpty ? "" : durationStr

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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if index < podcast.episodes.count - 1 {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
    }

    // MARK: - Actions

    private func playAll(_ podcast: PodcastDetailInfo) {
        guard !podcast.episodes.isEmpty else { return }
        let first = podcast.episodes[0]
        NowPlaying.shared.setQueue(podcast.episodes.map { $0.toSongItem() }, startIndex: 0)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
            } catch {
            }
        }
    }

    private func playEpisode(_ episode: EpisodeItem, in podcast: PodcastDetailInfo) {
        guard let index = podcast.episodes.firstIndex(where: { $0.videoId == episode.videoId }) else { return }
        NowPlaying.shared.setQueue(podcast.episodes.map { $0.toSongItem() }, startIndex: index)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: episode.videoId)
            } catch {
            }
        }
    }
}

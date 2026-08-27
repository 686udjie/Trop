//
//  SongMenuSheet.swift
//  Trop
//
//  Created by 686udjie on 26/08/2026.
//

import SwiftUI

struct SongMenuSheet: View {
    let song: SongItem
    var onNavigate: ((DetailRoute) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    enum Destination: Hashable {
        case details
    }

    @State private var isInLibrary = false
    @State private var isPinned = false
    @State private var showPlaylistPicker = false
    @State private var showArtistPicker = false
    @State private var isResolvingArtist = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    actionGrid
                    menuCard {
                        menuRow(
                            icon: "text.insert",
                            title: "Play Next",
                            subtitle: "Add to the queue, next in line"
                        ) { playNext() }
                        Divider()
                        menuRow(
                            icon: "list.bullet",
                            title: "Add to Queue",
                            subtitle: "Add to the end of the queue"
                        ) { addToQueue() }
                        Divider()
                        menuRow(
                            icon: isPinned ? "pin.fill" : "pin",
                            title: isPinned ? "Unpin from Quick Picks" : "Pin to Quick Picks"
                        ) { Task { await togglePin() } }
                        Divider()
                        libraryRow
                        Divider()
                        menuRow(
                            icon: "music.mic",
                            title: "View Artist",
                            subtitle: song.artistNamesDisplay
                        ) { handleViewArtist() }
                        if let albumId = song.firstAlbumBrowseId {
                            Divider()
                            menuRow(
                                icon: "record.circle",
                                title: "View Album",
                                subtitle: song.album
                            ) { navigate(.album(browseId: albumId)) }
                        }
                        Divider()
                        downloadRow
                    }
                    menuCard {
                        NavigationLink(value: Destination.details) {
                            menuRowLabel(
                                icon: "info.circle",
                                title: "Details",
                                subtitle: "Metadata & stream information"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .details:
                    SongDetailsView(song: song)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("View Artist", isPresented: $showArtistPicker, titleVisibility: .visible) {
            ForEach(song.artists.filter { !$0.name.isEmpty }, id: \.self) { artist in
                Button(artist.name) {
                    openArtist(artist)
                }
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            AddSongToPlaylistSheet(song: song)
        }
        .task { await loadStates() }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: song.title,
                    font: .headline,
                    frameHeight: 24,
                    textColor: .primary
                )
                Text(song.artistNamesDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await toggleLibrary() }
            } label: {
                Image(systemName: isInLibrary ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(isInLibrary ? .red : .secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Action Grid

    private var actionGrid: some View {
        HStack(spacing: 1) {
            actionButton(icon: "dot.radiowaves.left.and.right", label: "Start Radio") {
                startRadio()
            }
            actionButton(icon: "music.note.list", label: "Playlist") {
                showPlaylistPicker = true
            }
            actionButton(icon: "square.and.arrow.up", label: "Share") {
                share()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(settings.accentColor)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Menu Rows

    private var libraryRow: some View {
        menuRow(
            icon: isInLibrary ? "books.vertical.fill" : "books.vertical",
            title: isInLibrary ? "Remove from Library" : "Add to Library"
        ) { Task { await toggleLibrary() } }
    }

    @ViewBuilder
    private var downloadRow: some View {
        switch downloadState {
        case .downloading(let fraction):
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading…")
                        .font(.body)
                        .foregroundStyle(.primary)
                    ProgressView(value: fraction)
                        .tint(settings.accentColor)
                }
                Text("\(Int(fraction * 100))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    Task {
                        await downloadManager.delete(videoId: song.videoId)
                        dismiss()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

        case .completed:
            menuRowLabel(
                icon: "checkmark.circle.fill",
                title: "Downloaded",
                subtitle: "Available offline"
            )
            Divider()
            menuRow(
                icon: "trash",
                title: "Remove Download",
                destructive: true
            ) {
                Task {
                    await downloadManager.delete(videoId: song.videoId)
                    dismiss()
                }
            }

        case .failed(let message):
            menuRow(
                icon: "exclamationmark.triangle",
                title: "Retry Download",
                subtitle: message
            ) {
                Task {
                    await downloadManager.download(song: song)
                    dismiss()
                }
            }

        case .notStarted:
            menuRow(icon: "square.and.arrow.down", title: "Download") {
                Task {
                    await downloadManager.download(song: song)
                    dismiss()
                }
            }
        }
    }

    private func menuRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            menuRowLabel(icon: icon, title: title, subtitle: subtitle, destructive: destructive)
        }
        .buttonStyle(.plain)
    }

    private func menuRowLabel(
        icon: String,
        title: String,
        subtitle: String? = nil,
        destructive: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(destructive ? Color.red : settings.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Card Building Blocks

    @ViewBuilder
    private func menuCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - State

    private var downloadState: DownloadManager.DownloadState {
        if let state = downloadManager.downloads[song.videoId], state != .notStarted {
            return state
        }
        return downloadManager.isDownloaded(videoId: song.videoId) ? .completed : .notStarted
    }

    private func loadStates() async {
        if let entity = try? await DatabaseService.shared.fetchOne(SongEntity.self, key: song.videoId) {
            isInLibrary = entity.inLibrary != nil
        }
        isPinned = (try? await DatabaseService.shared.isPinnedToSpeedDial(videoId: song.videoId)) ?? false
    }

    // MARK: - Actions

    private func toggleLibrary() async {
        let db = DatabaseService.shared
        let target = !isInLibrary
        isInLibrary = target
        do {
            let entity = try await db.fetchOne(SongEntity.self, key: song.videoId)
            if target {
                try await MutationService.shared.addToLibrary(
                    videoId: song.videoId,
                    addToken: entity?.libraryAddToken ?? ""
                )
            } else {
                try await MutationService.shared.removeFromLibrary(
                    videoId: song.videoId,
                    removeToken: entity?.libraryRemoveToken ?? ""
                )
            }
        } catch {
            isInLibrary = !target
        }
    }

    private func togglePin() async {
        let db = DatabaseService.shared
        let target = !isPinned
        isPinned = target
        do {
            if target {
                try await db.pinToSpeedDial(song: song)
            } else {
                try await db.removeFromSpeedDial(videoId: song.videoId)
            }
        } catch {
            isPinned = !target
        }
    }

    private func startRadio() {
        let isCurrentSong = NowPlaying.shared.videoId == song.videoId
        if !isCurrentSong {
            NowPlaying.shared.setQueue([song], startIndex: 0)
            Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId) }
        }
        Task {
            guard let radio = try? await PersonalizationService.shared.fetchRadio(videoId: song.videoId),
                  radio.songs.count > 1 else { return }
            guard NowPlaying.shared.videoId == song.videoId else { return }
            NowPlaying.shared.queueSongs = radio.songs
            NowPlaying.shared.queueIndex = radio.currentIndex
        }
        dismiss()
    }

    private func playNext() {
        let np = NowPlaying.shared
        let insertIndex = min(np.queueIndex + 1, np.queueSongs.count)
        np.queueSongs.insert(song, at: insertIndex)
        np.repairQueueIndex()
        np.persistQueueState()
        dismiss()
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(song)
        np.persistQueueState()
        dismiss()
    }

    private func share() {
        let activityVC = UIActivityViewController(
            activityItems: [song.webUrl],
            applicationActivities: nil
        )
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(activityVC, animated: true)
        dismiss()
    }

    private func navigate(_ route: DetailRoute) {
        dismiss()
        onNavigate?(route)
    }

    private func handleViewArtist() {
        guard !isResolvingArtist else { return }
        let namedArtists = song.artists.filter { !$0.name.isEmpty }
        if namedArtists.count > 1 {
            showArtistPicker = true
            return
        }
        guard let artist = namedArtists.first else { return }
        openArtist(artist)
    }

    private func openArtist(_ artist: YTArtist) {
        if let id = artist.id {
            navigate(.artist(browseId: id))
            return
        }
        resolveArtistByName(artist.name)
    }

    private func resolveArtistByName(_ name: String) {
        guard !name.isEmpty else { return }
        isResolvingArtist = true
        Task {
            defer { isResolvingArtist = false }
            var browseId: String?
            do {
                let json = try await SearchService.shared.search(query: name)
                browseId = SearchParser.parseSearchResults(from: json)
                    .flatMap(\.items)
                    .compactMap { item -> String? in
                        if case .artist(let artist) = item { return artist.browseId }
                        return nil
                    }
                    .first
            } catch {
                browseId = nil
            }
            if let browseId {
                navigate(.artist(browseId: browseId))
            }
        }
    }
}

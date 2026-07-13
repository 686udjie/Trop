//
//  HistoryView.swift
//  Trop
//
//  Created by 686udjie on 13/07/2026.
//

import SwiftUI

struct HistoryScreenView: View {
    @State private var viewModel = HistoryView()
    @State private var isSelecting = false
    @State private var selectedEvents: Set<Event> = []

    private var allEvents: [Event] {
        viewModel.groupedEntries.flatMap(\.entries).map(\.event)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Source", selection: $viewModel.source) {
                ForEach(HistorySource.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.source == .local {
                    localHistoryContent
                } else {
                    remoteHistoryContent
                }
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .navigationBarBackButtonHidden(isSelecting)
        .onChange(of: viewModel.source) { _, newSource in
            if isSelecting {
                isSelecting = false
                selectedEvents.removeAll()
            }
            if newSource == .remote {
                Task { await viewModel.loadRemote() }
            }
        }
        .task { await viewModel.load() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.source == .local && !viewModel.groupedEntries.isEmpty {
            if isSelecting {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isSelecting = false
                        selectedEvents.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedEvents.count == allEvents.count {
                        Button("Deselect All") { selectedEvents.removeAll() }
                    } else {
                        Button("Select All") { selectedEvents = Set(allEvents) }
                    }
                }
                if !selectedEvents.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteEvents(Array(selectedEvents))
                                selectedEvents.removeAll()
                                isSelecting = false
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Select") { isSelecting = true }
                }
            }
        }
    }

    // MARK: - Local

    private var localHistoryContent: some View {
        Group {
            if viewModel.groupedEntries.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Songs you play will appear here.")
                )
            } else {
                localList
            }
        }
    }

    private var localList: some View {
        List {
            ForEach(viewModel.groupedEntries.indices, id: \.self) { sectionIndex in
                let section = viewModel.groupedEntries[sectionIndex]
                Section {
                    ForEach(section.entries, id: \.event) { entry in
                        localRow(entry)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(section.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func localRow(_ entry: DatabaseService.HistoryEntry) -> some View {
        if let song = entry.song.map({ SongItem(entity: $0) }) {
            let allItems = viewModel.groupedEntries.flatMap(\.entries).compactMap { $0.song.map(SongItem.init(entity:)) }
            let isSelected = selectedEvents.contains(entry.event)
            HStack(spacing: 0) {
                if isSelecting {
                    Button {
                        if isSelected {
                            selectedEvents.remove(entry.event)
                        } else {
                            selectedEvents.insert(entry.event)
                        }
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? .blue : .secondary)
                            .padding(.leading, 16)
                            .padding(.trailing, 4)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if isSelecting {
                        if isSelected {
                            selectedEvents.remove(entry.event)
                        } else {
                            selectedEvents.insert(entry.event)
                        }
                    } else {
                        if let index = allItems.firstIndex(where: { $0.videoId == song.videoId }) {
                            NowPlaying.shared.setQueue(allItems, startIndex: index)
                        } else {
                            NowPlaying.shared.setQueue([song], startIndex: 0)
                        }
                        Task {
                            try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
                        }
                    }
                } label: {
                    PlaylistSongRow(song: song)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteEvents([entry.event]) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Remote

    private var remoteHistoryContent: some View {
        Group {
            if viewModel.isRemoteLoading {
                loadingView
            } else if let error = viewModel.remoteError {
                ContentUnavailableView(
                    "Couldn't load history",
                    systemImage: "exclamationmark.circle",
                    description: Text(error.localizedDescription)
                )
            } else if viewModel.remoteSections.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Sign in to see your YouTube Music history.")
                )
            } else {
                remoteList
            }
        }
    }

    private var remoteList: some View {
        List {
            ForEach(viewModel.remoteSections.indices, id: \.self) { sectionIndex in
                let section = viewModel.remoteSections[sectionIndex]
                Section {
                    ForEach(section.songs, id: \.videoId) { song in
                        Button {
                            if let index = section.songs.firstIndex(where: { $0.videoId == song.videoId }) {
                                NowPlaying.shared.setQueue(section.songs, startIndex: index)
                            } else {
                                NowPlaying.shared.setQueue([song], startIndex: 0)
                            }
                            Task {
                                try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
                            }
                        } label: {
                            PlaylistSongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(section.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .listStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Loading history...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

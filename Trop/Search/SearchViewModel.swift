//
//  SearchViewModel.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    var searchText = ""
    var isFocused: Bool? = false

    var suggestions: [String] = []
    var localSongs: [SongEntity] = []
    var localArtists: [ArtistEntity] = []
    var localAlbums: [AlbumEntity] = []
    var localPlaylists: [PlaylistEntity] = []

    var searchSections: [SearchSection] = []
    var selectedSectionFilter: String?
    var isShowingLibrary = false

    var libraryFilterSections: [SearchSection] {
        var sections: [SearchSection] = []
        if !localSongs.isEmpty {
            sections.append(SearchSection(title: "Songs", items: localSongs.map { YTItem.song(SongItem(entity: $0)) }))
        }
        if !localAlbums.isEmpty {
            sections.append(SearchSection(title: "Albums", items: localAlbums.map { YTItem.album(AlbumItem(entity: $0)) }))
        }
        if !localArtists.isEmpty {
            sections.append(SearchSection(title: "Artists", items: localArtists.map { YTItem.artist(ArtistItem(entity: $0)) }))
        }
        if !localPlaylists.isEmpty {
            sections.append(SearchSection(title: "Playlists", items: localPlaylists.map { YTItem.playlist(PlaylistItem(entity: $0)) }))
        }
        return sections
    }

    var filteredSections: [SearchSection] {
        if isShowingLibrary {
            return libraryFilterSections
        }
        guard let filter = selectedSectionFilter else { return searchSections }
        return searchSections.filter { $0.title == filter }
    }

    var availableFilters: [String] {
        var filters = ["Library"]
        let order = ["Songs", "Albums", "Artists", "Playlists", "Podcasts", "Episodes", "Videos"]
        filters.append(contentsOf: order.filter { Set(searchSections.map(\.title)).contains($0) })
        return filters
    }

    var searchHistory: [SearchHistoryEntity] = []

    var isLoading = false
    var error: Error?

    private var suggestionsTask: Task<Void, Never>?
    private var localSearchTask: Task<Void, Never>?

    private static let historyKey = "Search.history"
    private static let historyNewestFirstKey = "Search.historyNewestFirst"
    private static let maxHistoryEntries = 20

    init() {
        loadSearchHistory()
    }

    private func saveHistory() {
        UserDefaults.standard.set(searchHistory.map(\.query), forKey: Self.historyKey)
    }

    func loadSearchHistory() {
        var queries = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []

        if !UserDefaults.standard.bool(forKey: Self.historyNewestFirstKey) {
            queries.reverse()
            UserDefaults.standard.set(queries, forKey: Self.historyKey)
            UserDefaults.standard.set(true, forKey: Self.historyNewestFirstKey)
        }

        searchHistory = queries.map { SearchHistoryEntity(query: $0, timestamp: Date()) }
    }

    func onSearchTextChange() {
        suggestionsTask?.cancel()
        localSearchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSuggestions()
            return
        }

        suggestionsTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let results = try await SearchService.shared.searchSuggestions(input: query)
                await MainActor.run {
                    self.suggestions = results
                }
            } catch {
                if !self.isCancellation(error) {
                    Log.search.error("Suggestions failed: \(error)")
                }
            }
        }

        localSearchTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            do {
                let results = try await SearchService.shared.localSearch(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.localSongs = results.songs
                    self.localArtists = results.artists
                    self.localAlbums = results.albums
                    self.localPlaylists = results.playlists
                }
            } catch {
                if !self.isCancellation(error) {
                    Log.search.error("Local search failed: \(error)")
                }
            }
        }
    }

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        suggestionsTask?.cancel()
        localSearchTask?.cancel()

        isFocused = false
        isLoading = true
        error = nil

        updateHistory(query: query)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                async let localResults = try? SearchService.shared.localSearch(query: query)
                let searchRaw = try await SearchService.shared.search(query: query)

                if let results = await localResults {
                    await MainActor.run {
                        self.localSongs = results.songs
                        self.localArtists = results.artists
                        self.localAlbums = results.albums
                        self.localPlaylists = results.playlists
                    }
                }

                let sections = SearchParser.parseSearchResults(from: searchRaw)
                await MainActor.run {
                    self.searchSections = sections
                    self.selectedSectionFilter = nil
                    self.isShowingLibrary = false
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    if !self.isCancellation(error) {
                        self.error = error
                    }
                    self.isLoading = false
                }
            }
        }
    }

    func clearSearch() {
        searchText = ""
        searchSections = []
        selectedSectionFilter = nil
        isShowingLibrary = false
        clearSuggestions()
    }

    func clearSearchHistory() {
        searchHistory = []
        saveHistory()
    }

    func deleteSearchHistoryEntry(_ entry: SearchHistoryEntity) {
        searchHistory.removeAll { $0.query == entry.query }
        saveHistory()
    }

    private func updateHistory(query: String) {
        guard !query.isEmpty else { return }

        var newHistory = searchHistory.map(\.query)
        if let index = newHistory.firstIndex(of: query) {
            newHistory.remove(at: index)
        }
        newHistory.insert(query, at: 0)

        if newHistory.count > Self.maxHistoryEntries {
            newHistory.removeLast()
        }

        UserDefaults.standard.set(newHistory, forKey: Self.historyKey)
        UserDefaults.standard.set(true, forKey: Self.historyNewestFirstKey)
        searchHistory = newHistory.map { SearchHistoryEntity(query: $0, timestamp: Date()) }
    }

    // MARK: - Private

    private func clearSuggestions() {
        suggestions = []
        localSongs = []
        localArtists = []
        localAlbums = []
        localPlaylists = []
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled || error is CancellationError
    }
}

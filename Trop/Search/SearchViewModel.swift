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

    var filteredSections: [SearchSection] {
        guard let filter = selectedSectionFilter else { return searchSections }
        return searchSections.filter { $0.title == filter }
    }

    var availableFilters: [String] {
        let filters = Set(searchSections.map(\.title))
        let order = ["Songs", "Albums", "Artists", "Playlists", "Podcasts", "Episodes", "Videos"]
        return order.filter { filters.contains($0) }
    }

    var searchHistory: [SearchHistoryEntity] = []

    var isLoading = false
    var error: Error?

    private var suggestionsTask: Task<Void, Never>?
    private var localSearchTask: Task<Void, Never>?

    private static let historyKey = "Search.history"
    private static let maxHistoryEntries = 20

    init() {
        searchHistory = (UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []).map {
            SearchHistoryEntity(query: $0, timestamp: Date())
        }
    }

    private func saveHistory() {
        UserDefaults.standard.set(searchHistory.map(\.query), forKey: Self.historyKey)
    }

    func loadSearchHistory() {
        let queries = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
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
                    print("[Search] Suggestions failed: \(error)")
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
                    print("[Search] Local search failed: \(error)")
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
                let raw = try await SearchService.shared.search(query: query)
                let sections = SearchParser.parseSearchResults(from: raw)
                await MainActor.run {
                    self.searchSections = sections
                    self.selectedSectionFilter = nil
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
        clearSuggestions()
    }

    func clearSearchHistory() {
        searchHistory = []
        saveHistory()
    }

    private func updateHistory(query: String) {
        guard !query.isEmpty else { return }

        var newHistory = searchHistory.map(\.query)
        if let index = newHistory.firstIndex(of: query) {
            newHistory.remove(at: index)
        }
        newHistory.append(query)

        if newHistory.count > Self.maxHistoryEntries {
            newHistory.removeFirst()
        }

        UserDefaults.standard.set(newHistory, forKey: Self.historyKey)
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

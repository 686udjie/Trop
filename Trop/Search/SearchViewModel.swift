//
//  SearchViewModel.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation
import SwiftUI

/// Drives the search screen.
///
/// The native search field owns its text lifecycle and may clear itself at any
/// moment (e.g. right after submitting, when the search session ends). Results
/// are therefore decoupled from the live field text: they belong to the last
/// *submitted* query and stay visible until a new submission replaces them.
@MainActor
@Observable
final class SearchViewModel {

    // MARK: - Phase

    enum Phase {
        /// Nothing submitted yet: recent searches / empty state.
        case idle
        /// Composing a query: live suggestions + local library matches.
        case typing
        /// Fetching results for the submitted query.
        case loading
        /// Showing results for the submitted query.
        case results
        /// Submitted query returned nothing.
        case noResults
        /// Submission failed.
        case failed
    }

    private(set) var phase: Phase = .idle

    // MARK: - Field & results

    /// Live text of the search field.
    var fieldText = "" {
        didSet {
            guard fieldText != oldValue else { return }
            handleFieldTextChange()
        }
    }

    /// Query whose results are currently held (if any).
    private(set) var submittedQuery = ""

    private(set) var results: [SearchSection] = []

    // MARK: - Typing state

    var suggestions: [String] = []
    var localSongs: [SongEntity] = []
    var localArtists: [ArtistEntity] = []
    var localAlbums: [AlbumEntity] = []
    var localPlaylists: [PlaylistEntity] = []

    // MARK: - Filtering

    var selectedSectionFilter: String?
    var isShowingLibrary = false

    // MARK: - Submission outcome

    var error: Error?

    // MARK: - History

    var searchHistory: [SearchHistoryEntity] = []

    private var suggestionsTask: Task<Void, Never>?
    private var localSearchTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

    private static let historyKey = "Search.history"
    private static let historyNewestFirstKey = "Search.historyNewestFirst"
    private static let maxHistoryEntries = 20

    init() {
        loadSearchHistory()
    }

    // MARK: - Derived content

    var availableFilters: [String] {
        var filters = ["Library"]
        let order = ["Songs", "Albums", "Artists", "Playlists", "Podcasts", "Episodes", "Videos"]
        let titles = Set(results.map(\.title))
        filters.append(contentsOf: order.filter { titles.contains($0) })
        return filters
    }

    var filteredResults: [SearchSection] {
        if isShowingLibrary {
            return librarySections
        }
        guard let filter = selectedSectionFilter else { return results }
        return results.filter { $0.title == filter }
    }

    private var librarySections: [SearchSection] {
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

    // MARK: - Submission

    /// Submits the given text (or the current field text).
    func submit(_ text: String? = nil) {
        if let text {
            fieldText = text
        }

        let query = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // Enter .loading FIRST so clearing the field below is treated as part
        // of the submission rather than as new composition input.
        phase = .loading
        submittedQuery = query
        error = nil
        selectedSectionFilter = nil
        isShowingLibrary = false

        updateHistory(query: query)
        cancelTasks()

        fetchTask = Task { [weak self] in
            await self?.fetchResults(for: query)
        }
    }

    private func fetchResults(for query: String) async {
        guard !Task.isCancelled else { return }
        do {
            async let localResults = try? SearchService.shared.localSearch(query: query)
            let searchRaw = try await SearchService.shared.search(query: query)

            guard !Task.isCancelled, query == submittedQuery else { return }

            if let local = await localResults {
                localSongs = local.songs
                localArtists = local.artists
                localAlbums = local.albums
                localPlaylists = local.playlists
            }

            guard !Task.isCancelled, query == submittedQuery else { return }

            results = SearchParser.parseSearchResults(from: searchRaw)
            selectedSectionFilter = nil
            isShowingLibrary = false
            phase = results.isEmpty ? .noResults : .results
        } catch {
            guard !Task.isCancelled, query == submittedQuery else { return }
            if !Self.isCancellation(error) {
                Log.search.error("Submit failed: \(error)")
                self.error = error
                phase = .failed
            }
        }
    }

    // MARK: - Field changes

    private func handleFieldTextChange() {
        // While fetching, the field is owned by the submission flow.
        if phase == .loading {
            return
        }

        let query = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)

        // An emptied field (X button, or deleting the query) exits the current
        // search: results are discarded and the screen returns to the
        // recent-searches state.
        if query.isEmpty {
            cancelTasks()
            clearTypingData()
            submittedQuery = ""
            results = []
            selectedSectionFilter = nil
            isShowingLibrary = false
            error = nil
            phase = .idle
            return
        }

        beginTyping(query)
    }

    private func beginTyping(_ query: String) {
        phase = .typing
        cancelTasks()
        scheduleSuggestions(for: query)
        scheduleLocalSearch(for: query)
    }

    // MARK: - Suggestions & local search

    private func scheduleSuggestions(for query: String) {
        suggestionsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                self?.suggestions = try await SearchService.shared.searchSuggestions(input: query)
            } catch {
                if !Self.isCancellation(error) {
                    Log.search.error("Suggestions failed: \(error)")
                }
            }
        }
    }

    private func scheduleLocalSearch(for query: String) {
        localSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            do {
                let results = try await SearchService.shared.localSearch(query: query)
                guard !Task.isCancelled else { return }
                self?.localSongs = results.songs
                self?.localArtists = results.artists
                self?.localAlbums = results.albums
                self?.localPlaylists = results.playlists
            } catch {
                if !Self.isCancellation(error) {
                    Log.search.error("Local search failed: \(error)")
                }
            }
        }
    }

    // MARK: - History

    func loadSearchHistory() {
        var queries = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []

        if !UserDefaults.standard.bool(forKey: Self.historyNewestFirstKey) {
            queries.reverse()
            UserDefaults.standard.set(queries, forKey: Self.historyKey)
            UserDefaults.standard.set(true, forKey: Self.historyNewestFirstKey)
        }

        searchHistory = queries.map { SearchHistoryEntity(query: $0, timestamp: Date()) }
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
        guard SettingsStore.shared.trackSearchHistory else { return }

        var queries = searchHistory.map(\.query)
        if let index = queries.firstIndex(of: query) {
            queries.remove(at: index)
        }
        queries.insert(query, at: 0)

        if queries.count > Self.maxHistoryEntries {
            queries.removeLast()
        }

        UserDefaults.standard.set(queries, forKey: Self.historyKey)
        UserDefaults.standard.set(true, forKey: Self.historyNewestFirstKey)
        searchHistory = queries.map { SearchHistoryEntity(query: $0, timestamp: Date()) }
    }

    private func saveHistory() {
        UserDefaults.standard.set(searchHistory.map(\.query), forKey: Self.historyKey)
    }

    // MARK: - Private helpers

    private func cancelTasks() {
        suggestionsTask?.cancel()
        localSearchTask?.cancel()
        fetchTask?.cancel()
    }

    private func clearTypingData() {
        suggestions = []
        localSongs = []
        localArtists = []
        localAlbums = []
        localPlaylists = []
    }

    private static func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled || error is CancellationError
    }
}

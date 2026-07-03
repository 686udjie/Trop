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

    var isLoading = false
    var error: Error?

    private var suggestionsTask: Task<Void, Never>?
    private var localSearchTask: Task<Void, Never>?

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

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let raw = try await SearchService.shared.search(query: query)
                let sections = SearchParser.parseSearchResults(from: raw)
                await MainActor.run {
                    self.searchSections = sections
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
        clearSuggestions()
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

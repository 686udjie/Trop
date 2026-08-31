//
//  HistoryViewModel.swift
//  Trop
//
//  Created by 686udjie on 13/07/2026.
//

import Foundation

enum HistorySource: String, CaseIterable, Sendable {
    case local = "Local"
    case remote = "Remote"
}

@MainActor
@Observable
final class HistoryView {
    var groupedEntries: [(title: String, entries: [DatabaseService.HistoryEntry])] = []
    var remoteSections: [(title: String, songs: [SongItem])] = []
    var source: HistorySource = .local
    var isLoading = true
    var isRemoteLoading = false
    var remoteError: Error?

    private let db = DatabaseService.shared

    func load() async {
        isLoading = true
        await loadLocal()
        isLoading = false
    }

    func loadLocal() async {
        do {
            let raw = try await db.fetchHistory(limit: 100)
            groupedEntries = Self.groupByDate(raw)
        } catch {
            Log.historyView.error("Failed to load local history: \(error)")
        }
    }

    func loadRemote() async {
        guard source == .remote else { return }
        isRemoteLoading = true
        remoteError = nil
        do {
            let json = try await InnerTube.shared.browse(browseId: "FEmusic_history")
            let sections = Self.parseRemoteHistory(from: json)
            remoteSections = sections
        } catch {
            Log.historyView.error("Failed to load remote history: \(error)")
            remoteError = error
        }
        isRemoteLoading = false
    }

    func switchSource(_ newSource: HistorySource) {
        guard newSource != source else { return }
        source = newSource
        if newSource == .remote && remoteSections.isEmpty {
            Task { await loadRemote() }
        }
    }

    // MARK: - Local group by date

    private static func groupByDate(_ entries: [DatabaseService.HistoryEntry]) -> [(String, [DatabaseService.HistoryEntry])] {
        guard !entries.isEmpty else { return [] }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.event.timestamp)
        }

        return grouped.keys
            .sorted(by: >)
            .compactMap { day -> (String, [DatabaseService.HistoryEntry])? in
                guard let dayEntries = grouped[day], !dayEntries.isEmpty else { return nil }
                let sorted = dayEntries.sorted { $0.event.timestamp > $1.event.timestamp }
                return (title(for: day), sorted)
            }
    }

    private static func title(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    func deleteEvents(_ events: [Event]) async {
        for event in events {
            _ = try? await db.delete(event)
        }
        await loadLocal()
    }

    // MARK: - Remote history parse

    private static func parseRemoteHistory(from json: [String: Any]) -> [(title: String, songs: [SongItem])] {
        guard let contents = json["contents"] as? [String: Any] else {
            Log.historyView.debug("No 'contents' in response, keys: \(json.keys.sorted())")
            return []
        }
        guard let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any] else {
            Log.historyView.debug("No singleColumnBrowseResultsRenderer, keys: \(contents.keys.sorted())")
            return []
        }
        guard let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let shelfList = sectionList["contents"] as? [[String: Any]] else {
            Log.historyView.debug("Couldn't navigate to sectionListRenderer.contents")
            return []
        }

        var sections: [(title: String, songs: [SongItem])] = []

        for shelfDict in shelfList {
            guard let shelf = shelfDict["musicShelfRenderer"] as? [String: Any] else {
                Log.historyView.debug("Skipping non-musicShelfRenderer: \(shelfDict.keys.sorted())")
                continue
            }

            let title = extractShelfTitle(shelf) ?? "Unknown"
            guard let items = shelf["contents"] as? [[String: Any]] else { continue }

            var songs: [SongItem] = []
            for itemDict in items {
                guard let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any] else { continue }
                if let song = SongItem.from(renderer) {
                    songs.append(song)
                }
            }

            if !songs.isEmpty {
                sections.append((title, songs))
            }
        }

        return sections
    }

    private static func extractShelfTitle(_ shelf: [String: Any]) -> String? {
        guard let titleDict = shelf["title"] as? [String: Any],
              let runs = titleDict["runs"] as? [[String: Any]],
              let first = runs.first,
              let text = first["text"] as? String else {
            return nil
        }
        return text
    }
}

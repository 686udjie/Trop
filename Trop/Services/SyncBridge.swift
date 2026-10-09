//
//  SyncBridge.swift
//  Trop
//
//  Created by 686udjie on 09/10/2026.
//

enum SyncBridge {
    static let store = TropLibraryStore()
    static let librarySync = LibrarySyncService(client: InnerTubeClient.tropShared, store: store)
    static let playlistDetail = PlaylistDetailService(client: InnerTubeClient.tropShared, store: store)
    static let mutations = MutationService(client: InnerTubeClient.tropShared, store: store)
    static let incremental = IncrementalSyncService(client: InnerTubeClient.tropShared, librarySync: librarySync)

    static var options: LibrarySyncOptions {
        let settings = SettingsStore.shared
        return LibrarySyncOptions(
            syncArtists: settings.syncArtists,
            syncPlaylists: settings.syncPlaylists,
            syncAlbums: settings.syncAlbums,
            syncPodcasts: settings.syncPodcasts,
            syncSongs: settings.syncSongs
        )
    }

    static func checkAndSyncIfStale() async {
        await incremental.checkAndSyncIfStale(options: options) {
            await LikeStore.shared.refresh()
        }
    }

    static func forceFullSync() async {
        await incremental.forceFullSync(options: options) {
            await LikeStore.shared.refresh()
        }
    }
}

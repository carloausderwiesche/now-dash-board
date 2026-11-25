// Getting at a folder outside the app, and keeping access to it.
//
// iOS (and the sandboxed Mac app) can't just open any path. You pick the
// folder once in the system's folder picker; the app saves a *bookmark* (a
// small token for that folder) and uses it on the next launch. Every access
// is wrapped in start/stopAccessingSecurityScopedResource, and every read
// goes through NSFileCoordinator, so a file Obsidian or iCloud is writing at
// that moment is read before or after the write, never halfway.

import Foundation
import NowboardKit

enum FolderAccess {
    private static let key = "tasksFolderBookmark"

    // A plain bookmark on both platforms. The Mac app isn't sandboxed (ADR
    // 0009), so it needs no "security scope", and a plain bookmark keeps
    // working after a rebuild. On iOS the system grants access to a folder
    // picked in Files through the bookmark itself.
    private static let createOptions: URL.BookmarkCreationOptions = []
    private static let resolveOptions: URL.BookmarkResolutionOptions = []

    /// True if a folder was saved but can't be found any more (moved, deleted,
    /// or access lost). The board then says so instead of quietly showing the demo.
    static var lostFolder: Bool {
        UserDefaults.standard.data(forKey: key) != nil && restore() == nil
    }

    /// Saves a bookmark for a folder you just picked.
    static func remember(_ url: URL) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: createOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The folder from the saved bookmark, if there is one and it still works.
    static func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        // "Stale" means the folder moved or was renamed: save a fresh bookmark.
        if stale { try? remember(url) }
        return url
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Reads every task in the folder, with the folder's access switched on
    /// and the read coordinated with other apps.
    ///
    /// Swift note: `nonisolated` lets this run on a background thread even
    /// though the rest of the app lives on the main thread.
    nonisolated static func loadTasks(from url: URL) -> Result<[BoardTask], Error> {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        var result: Result<[BoardTask], Error> = .success([])
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { folder in
            result = Result { try TaskFolder(url: folder).loadAll() }
        }
        if let coordinationError { return .failure(coordinationError) }
        return result
    }

    /// Runs `change` on the Tasks folder with access switched on and the
    /// write coordinated with other apps (Obsidian, iCloud), so nobody reads
    /// a file while we write it.
    /// `presenter`: our own folder watcher. Telling the coordinator who's
    /// writing means the watcher isn't notified about our own writes.
    nonisolated static func write(in url: URL, presenter: NSFilePresenter? = nil, _ change: @Sendable (TaskFolder) throws -> Void) -> Error? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: url, options: [], error: &coordinationError) { folder in
            do {
                try change(TaskFolder(url: folder))
            } catch {
                failure = error
            }
        }
        return coordinationError ?? failure
    }
}

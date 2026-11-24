// Where the board's tasks come from: the demo, or a Tasks folder you picked.
// Holds the app's state; views read it and call its methods (like useBoard.ts).

import Foundation
import NowboardKit
import Observation

/// Swift note: `@Observable` makes SwiftUI redraw any view that read a property
/// when that property changes. `@MainActor` keeps all of this on the main
/// thread, where UI state has to live; Swift 6 checks that at compile time.
@MainActor
@Observable
final class BoardStore {
    enum Source: Equatable {
        case demo
        case folder(URL)
    }

    private(set) var tasks: [BoardTask] = []
    private(set) var source: Source = .demo
    private(set) var error: String?
    /// Theme, card size and categories; saved whenever they change.
    var settings: DeviceSettings {
        didSet { settings.save() }
    }
    /// The highlighted category (tap a header dot), or nil for all.
    var filter: String?
    /// The card whose detail panel is open.
    var openID: String?
    /// Quick add is showing.
    var adding = false

    var theme: Theme { Theme.named(settings.theme) }

    /// The lists on the board, for today's date.
    var lists: BoardLists {
        let day = { (d: Date) in String(TaskFormat.timestamp(d).prefix(10)) }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
        return BoardLists(tasks: tasks, today: day(.now), recentSince: day(weekAgo))
    }

    init() {
        settings = DeviceSettings.load()
        if let url = FolderAccess.restore() {
            source = .folder(url)
            watch(url)
        }
    }

    /// Watching the folder needs its access switched on for as long as we watch.
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var watchedURL: URL?

    private func watch(_ url: URL?) {
        watcher?.stop()
        watchedURL?.stopAccessingSecurityScopedResource()
        watcher = nil
        watchedURL = nil
        guard let url else { return }
        if url.startAccessingSecurityScopedResource() { watchedURL = url }
        watcher = FolderWatcher(url: url) { [weak self] in
            Task { await self?.reload() }
        }
    }

    /// For tests: a store on a given folder, with default settings and
    /// nothing remembered (the app's saved folder and settings stay untouched).
    init(testFolder: URL) {
        settings = DeviceSettings()
        source = .folder(testFolder)
        watch(testFolder)
    }

    #if DEBUG
        /// Snapshots of the demo board without forgetting the saved folder.
        func useDemoForSnapshot() {
            source = .demo
        }
    #endif

    /// Waits until every pending write has finished (and the board reloaded).
    func waitForWrites() async {
        await lastWrite?.value
    }

    /// Reads the tasks again: on launch, when the app comes back to the
    /// front, and on pull-to-refresh.
    func reload() async {
        switch source {
        case .demo:
            // The demo lives in memory: load it once, then keep your edits.
            if tasks.isEmpty { tasks = Demo.tasks() }
            error = nil
        case .folder(let url):
            // Reading many files is slow work; do it away from the main
            // thread (`Task.detached`), then come back with the result.
            // `Result` carries either the tasks or the error back.
            let result = await Task.detached { FolderAccess.loadTasks(from: url) }.value
            switch result {
            case .success(let loaded):
                tasks = loaded
                error = nil
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }

    /// You picked a Tasks folder (from the folder picker).
    func use(folder url: URL) async {
        do {
            try FolderAccess.remember(url)
            source = .folder(url)
            watch(url)
            await reload()
        } catch {
            self.error = "Couldn't open that folder: \(error.localizedDescription)"
        }
    }

    /// Back to the sample board.
    func useDemo() async {
        FolderAccess.forget()
        source = .demo
        watch(nil)
        tasks = []
        await reload()
    }

    /// The task's file, for "Open in Obsidian". Nil on the demo board.
    func fileURL(_ id: String) -> URL? {
        guard case .folder(let url) = source else { return nil }
        return url.appendingPathComponent(id)
    }

    /// `obsidian://open?path=…` opens a file in Obsidian by its full path.
    func obsidianURL(_ id: String) -> URL? {
        guard let file = fileURL(id) else { return nil }
        var parts = URLComponents()
        parts.scheme = "obsidian"
        parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "path", value: file.path)]
        return parts.url
    }

    func task(_ id: String) -> BoardTask? {
        tasks.first { $0.id == id }
    }

    // MARK: - Changing tasks
    //
    // Every change works the same way (like useBoard.ts): update `tasks` right
    // away so the screen reacts instantly, then write the file in the
    // background. Writes run one after another (`lastWrite` chains them), so
    // two quick changes can't overtake each other. After a write the folder is
    // read again, which picks up new file names (new tasks, renames). If a
    // write fails, the error shows and the board is reloaded from disk.

    private var lastWrite: Task<Void, Never>?

    /// Updates the screen with `local`, then (for a real folder) runs `disk`.
    private func change(_ local: (inout [BoardTask]) -> Void, disk: @escaping @Sendable (TaskFolder) throws -> Void) {
        local(&tasks)
        guard case .folder(let url) = source else { return }
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            let failure = await Task.detached { FolderAccess.write(in: url, disk) }.value
            // Reload first (it clears old errors), then show this one.
            await reload()
            if let failure {
                error = failure.localizedDescription
            }
        }
    }

    /// Saves changed copies of tasks (they keep their ids).
    private func save(_ changed: [BoardTask]) {
        guard !changed.isEmpty else { return }
        let byID = Dictionary(changed.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        change({ all in all = all.map { byID[$0.id] ?? $0 } }) { folder in
            for t in changed { try folder.save(t) }
        }
    }

    /// Moves a card into a list, before another card or at the end.
    func move(_ id: String, to status: TaskStatus, before: String? = nil) {
        save(BoardRules.planMove(tasks, id: id, to: status, before: before))
    }

    /// Moves a card to the top of a list.
    func moveToTop(_ id: String, of status: TaskStatus) {
        let first = lists(for: status).first { $0.id != id }
        move(id, to: status, before: first?.id)
    }

    private func lists(for status: TaskStatus) -> [BoardTask] {
        BoardLists.sorted(tasks.filter { $0.status == status })
    }

    /// Marks a task done now and ends its focus. Only its own file is written.
    func complete(_ id: String) {
        let now = TaskFormat.timestamp(.now)
        change({ all in
            if let i = all.firstIndex(where: { $0.id == id }) {
                all[i].status = .done
                all[i].focus = false
                all[i].done = now
            }
        }) { folder in try folder.complete(id, now: now) }
    }

    /// Undo: back to the top of Today, `done:` cleared.
    func reopen(_ id: String) {
        moveToTop(id, of: .today)
    }

    /// Any edit from the detail panel (checklist, notes, list, category).
    func update(_ task: BoardTask) {
        save([task])
    }

    /// The next category (tapping a card's dot).
    func cycleCategory(_ id: String) {
        guard var t = task(id) else { return }
        t.area = BoardRules.nextArea(after: t.area, in: settings.categories.map(\.id))
        save([t])
    }

    func setCategory(_ id: String, to area: String) {
        guard var t = task(id), t.area != area else { return }
        t.area = area
        save([t])
    }

    /// Focus on this card (only one at a time), or stop focusing.
    func toggleFocus(_ id: String) {
        guard let target = task(id) else { return }
        let on = !target.focus
        var changed: [BoardTask] = []
        for var t in tasks where t.id == id || (on && t.focus) {
            t.focus = t.id == id ? on : false
            changed.append(t)
        }
        save(changed)
    }

    /// A suggested task: accept → top of Backlog (keeps `from:`).
    func accept(_ id: String) {
        moveToTop(id, of: .backlog)
    }

    /// Renames the file to fit a new title.
    func rename(_ id: String, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let t = task(id), !title.isEmpty, title != t.title else { return }
        let order = t.order
        change({ all in
            if let i = all.firstIndex(where: { $0.id == id }) {
                all[i].title = title
                if case .demo = source { all[i].id = TaskFormat.stem(for: title) + ".md" }
            }
        }) { folder in try folder.rename(id, to: title, order: order) }
    }

    /// Deletes the task's file for good (also: dismissing a suggestion).
    func delete(_ id: String) {
        change({ all in all.removeAll { $0.id == id } }) { folder in try folder.delete(id) }
    }

    /// A new task on top of its list.
    func add(title: String, area: String, status: TaskStatus) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let new = BoardTask(
            title: title, status: status, area: area,
            order: BoardRules.topOrder(tasks, status), created: TaskFormat.timestamp(.now))
        change({ all in
            var shown = new
            // Until the file exists, a temporary id; the reload brings the real one.
            shown.id = "new-\(UUID().uuidString).md"
            if case .demo = source { shown.id = TaskFormat.stem(for: title) + ".md" }
            all.append(shown)
        }) { folder in try folder.save(new) }
    }
}

// Where the board's tasks come from: the demo, or a Tasks folder you picked.
// Holds the app's state; views read it and call its methods (like useBoard.ts).

import Foundation
import NowboardKit
import Observation
import SwiftUI

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
    /// What's shown in the error bar: a failed save first, else a failed load.
    var error: String? { writeError ?? loadError ?? settingsError }
    /// A save that failed. Stays until the next save works, so a reload
    /// (from the watcher, say) can't hide it.
    private(set) var writeError: String?
    private(set) var loadError: String?
    /// `.nowboard.json` couldn't be read (it isn't valid JSON).
    private(set) var settingsError: String?
    /// Theme, card size and categories, remembered on this device. With a
    /// Tasks folder, the categories come from its `.nowboard.json` (ADR 0011);
    /// change them with `setCategories`, which writes that file.
    var settings: DeviceSettings {
        didSet { if remembersSettings { settings.save() } }
    }
    /// Off in tests, so they never touch the app's real settings.
    @ObservationIgnored private var remembersSettings = true
    /// `.nowboard.json` was missing and we've started it from this device's
    /// categories (once per folder, so a failing write can't loop).
    @ObservationIgnored private var seededCategories = false
    @ObservationIgnored private var categoriesSave: Task<Void, Never>?
    /// The highlighted category (tap a header dot), or nil for all.
    var filter: String?
    /// The card whose detail panel is open.
    var openID: String?
    /// Quick add is showing.
    var adding = false
    /// The settings popover (Mac) or sheet (iPhone) is showing.
    var showingSettings = false
    /// The header's tools, in window coordinates: the Mac's settings popover hangs under them.
    var settingsAnchor: CGRect = .zero
    /// Dragging cards (Mac).
    let drag = DragController()
    /// The card under the pointer (Mac): drawn above its neighbours.
    var hoveredID: String?
    /// Cards playing the finish animation, and how far each one flies.
    private(set) var finishing: [String: Finish] = [:]
    /// Measured by the views, in board coordinates: the Done number (where a
    /// finished card flies) and the bottom of the part of the board you can see.
    @ObservationIgnored var doneTarget: CGRect?
    @ObservationIgnored var visibleBottom: CGFloat = .infinity
    /// Finished elsewhere and waiting for their animation, one at a time.
    @ObservationIgnored private var incoming: [String] = []
    /// The file's version of every card that's waiting or playing; the board
    /// shows the old version until the card has landed.
    @ObservationIgnored private var held: [String: BoardTask] = [:]
    @ObservationIgnored private var playingIncoming = false
    /// Cards playing the delete animation.
    private(set) var deleting: Set<String> = []
    /// The task deleted a moment ago, which Undo can still bring back.
    private(set) var undoable: Deleted?
    @ObservationIgnored private var pendingDelete: Task<Void, Never>?
    /// Finished in this app: a reload that still sees them as open (it started
    /// before our write) mustn't play the animation a second time.
    @ObservationIgnored private var completedHere: Set<String> = []

    var theme: Theme { Theme.named(settings.theme) }

    /// The lists on the board, for today's date.
    var lists: BoardLists {
        let day = { (d: Date) in String(TaskFormat.timestamp(d).prefix(10)) }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
        return BoardLists(tasks: tasks, today: day(.now), recentSince: day(weekAgo))
    }

    /// What dropping a dragged card does: Done completes it, a list moves it.
    private func connectDrag() {
        drag.onDrop = { [weak self] id, target in
            guard let self else { return }
            if target.status == .done {
                self.finish(id)
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) {
                    self.move(id, to: target.status, before: target.beforeID)
                }
            }
        }
    }

    init() {
        settings = DeviceSettings.load()
        defer { connectDrag() }
        if let url = FolderAccess.restore() {
            source = .folder(url)
            watch(url)
        } else if FolderAccess.lostFolder {
            loadError = "Nowboard lost access to your Tasks folder. Choose it again: Settings → Choose Tasks folder…"
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
        remembersSettings = false
        source = .folder(testFolder)
        defer { connectDrag() }
        watch(testFolder)
    }

    #if DEBUG
        /// Snapshots of the demo board without forgetting the saved folder.
        func useDemoForSnapshot() {
            watch(nil)
            source = .demo
            tasks = []
        }

        var isDemo: Bool { source == .demo }
    #endif

    /// Waits until every pending write has finished (and the board reloaded).
    func waitForWrites() async {
        await categoriesSave?.value
        await pendingDelete?.value
        await lastWrite?.value
    }

    /// Reads the tasks again: on launch, when the app comes back to the
    /// front, and on pull-to-refresh.
    func reload() async {
        switch source {
        case .demo:
            // The demo lives in memory: load it once, then keep your edits.
            if tasks.isEmpty { tasks = Demo.tasks() }
        case .folder(let url):
            // Reading many files is slow work; do it away from the main
            // thread (`Task.detached`), then come back with the result.
            // `Result` carries either the tasks or the error back.
            let result = await Task.detached { FolderAccess.loadTasks(from: url) }.value
            switch result {
            case .success(let loaded):
                tasks = absorb(loaded)
                loadError = nil
                playNextIncoming()
            case .failure(let failure):
                loadError = failure.localizedDescription
            }
            useCategories(await Task.detached { FolderAccess.loadCategories(from: url) }.value)
        }
    }

    /// The categories from the Tasks folder. No file yet: start it from this
    /// device's categories, so the other devices pick them up.
    private func useCategories(_ result: Result<[CategoryRecord]?, Error>) {
        // An edit that isn't saved yet wins over the file (it's about to replace it).
        guard categoriesSave == nil else { return }
        switch result {
        case .success(let records?):
            settingsError = nil
            let cats = records.map(Category.init)
            if cats != settings.categories { settings.categories = cats }
        case .success(nil):
            settingsError = nil
            guard !seededCategories else { return }
            seededCategories = true
            writeCategories(settings.categories)
        case .failure(let failure):
            settingsError = failure.localizedDescription
        }
    }

    /// Changes the categories (add, rename, colour, reorder, delete): on
    /// screen at once, in `.nowboard.json` 0.4s after the last change, so
    /// typing a name isn't a write per key.
    func setCategories(_ cats: [Category]) {
        guard !cats.isEmpty else { return }
        settings.categories = cats
        guard case .folder = source else { return }
        categoriesSave?.cancel()
        categoriesSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            categoriesSave = nil
            writeCategories(cats)
        }
    }

    private func writeCategories(_ cats: [Category]) {
        let records = cats.map(\.record)
        change({ _ in }) { folder in try folder.saveCategories(records) }
    }

    /// You picked a Tasks folder (from the folder picker).
    func use(folder url: URL) async {
        do {
            try FolderAccess.remember(url)
            source = .folder(url)
            seededCategories = false
            watch(url)
            await reload()
        } catch {
            loadError = "Couldn't open that folder: \(error.localizedDescription)"
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
            let presenter = watcher
            let failure = await Task.detached { FolderAccess.write(in: url, presenter: presenter, disk) }.value
            writeError = failure?.localizedDescription
            await reload()
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

    /// Finishes a task with its animation (DESIGN.md, "Complete"): the ring
    /// fills and the title strikes through, then the card glides into the Done
    /// number and the task is marked done. `onDisk`: it was finished elsewhere,
    /// so nothing is written and the card lands as the file says. A card that
    /// isn't on screen lands at once.
    func finish(_ id: String, onDisk: BoardTask? = nil) {
        guard finishing[id] == nil else { return }
        guard drag.cardFrames[id] != nil else { return land(id, onDisk: onDisk) }
        withAnimation(.easeOut(duration: 0.25)) { finishing[id] = Finish(step: .ticked) }
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            let flight = flightToDone(id)
            withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.46)) {
                finishing[id] = Finish(step: .leaving, flight: flight)
            }
            try? await Task.sleep(for: .milliseconds(460))
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) { land(id, onDisk: onDisk) }
            // Cleared only once the card is gone: clearing it while the card
            // fades out would draw it back in its old place for a moment.
            try? await Task.sleep(for: .milliseconds(450))
            if finishing[id]?.step == .leaving { finishing[id] = nil }
        }
    }

    private func land(_ id: String, onDisk: BoardTask?) {
        guard let onDisk else { return complete(id) }
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i] = onDisk }
        held[id] = nil
        playingIncoming = false
        playNextIncoming()
    }

    /// From the card's centre to the Done number's. When Done is below what
    /// you can see, the card aims for the bottom edge instead.
    private func flightToDone(_ id: String) -> CGSize {
        guard let card = drag.cardFrames[id], let done = doneTarget else { return CGSize(width: 0, height: 300) }
        return CGSize(width: done.midX - card.midX, height: min(done.midY, visibleBottom - 24) - card.midY)
    }

    /// The board after a reload. Cards finished elsewhere keep their old
    /// version until their finish animation has played.
    private func absorb(_ loaded: [BoardTask]) -> [BoardTask] {
        let fresh = finishedElsewhere(before: tasks, after: loaded).filter {
            held[$0] == nil && finishing[$0] == nil && !completedHere.contains($0)
        }
        incoming += fresh
        let before = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result = loaded
        for i in result.indices where held[result[i].id] != nil || fresh.contains(result[i].id) {
            let id = result[i].id
            held[id] = result[i]
            if let old = before[id] { result[i] = old }
        }
        // A waiting card whose file is gone is simply forgotten.
        let present = Set(loaded.map(\.id))
        for id in held.keys where !present.contains(id) { held[id] = nil }
        incoming.removeAll { held[$0] == nil }
        return result
    }

    private func playNextIncoming() {
        guard !playingIncoming, !incoming.isEmpty else { return }
        let id = incoming.removeFirst()
        guard let disk = held[id] else { return playNextIncoming() }
        playingIncoming = true
        finish(id, onDisk: disk)
    }

    /// Marks a task done now and ends its focus, without the animation (see
    /// `finish`). Only its own file is written.
    func complete(_ id: String) {
        completedHere.insert(id)
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
        finishing[id] = nil
        completedHere.remove(id)
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
        // The card grows into focus on a soft spring with a little overshoot,
        // like something growing; the cards around it glide aside on the same
        // spring. Pausing settles back calmly, without the overshoot.
        withAnimation(on ? Self.focusSpring : Self.pauseSpring) {
            save(changed)
        }
    }

    static let focusSpring = Animation.spring(response: 0.55, dampingFraction: 0.72)
    static let pauseSpring = Animation.spring(response: 0.45, dampingFraction: 0.92)

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

    /// Deletes the task's file (also: dismissing a suggestion). The card
    /// shrinks, blurs and fades where it stands, then the file goes. For a
    /// few seconds Undo can bring it back (ADR 0010), so there's no "are you sure?".
    func delete(_ id: String) {
        guard let t = task(id), !deleting.contains(id) else { return }
        // Kept in memory, so Undo can write the file back byte for byte.
        let deleted = Deleted(task: t, text: fileURL(id).flatMap { try? String(contentsOf: $0, encoding: .utf8) })
        withAnimation(.easeOut(duration: 0.2)) { undoable = deleted }
        withAnimation(.easeIn(duration: 0.2)) { _ = deleting.insert(id) }
        pendingDelete = Task {
            try? await Task.sleep(for: .milliseconds(200))
            // Undo while it was still fading: nothing to delete.
            guard deleting.remove(id) != nil else { return }
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) {
                change({ all in all.removeAll { $0.id == id } }) { folder in try folder.delete(id) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undoable == deleted { withAnimation(.easeOut(duration: 0.2)) { undoable = nil } }
        }
    }

    /// Brings the last deleted task back, its file exactly as it was.
    func undoDelete() {
        guard let d = undoable else { return }
        withAnimation(.easeOut(duration: 0.2)) { undoable = nil }
        let id = d.task.id
        if withAnimation(.easeOut(duration: 0.2), { deleting.remove(id) }) != nil { return }
        withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) {
            change({ all in if !all.contains(where: { $0.id == id }) { all.append(d.task) } }) { folder in
                if let text = d.text {
                    try folder.restore(id, text: text)
                } else {
                    try folder.save(d.task)
                }
            }
        }
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

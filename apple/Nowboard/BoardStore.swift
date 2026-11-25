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
        }
    }

    /// Reads the tasks again: on launch, when the app comes back to the
    /// front, and on pull-to-refresh.
    func reload() async {
        switch source {
        case .demo:
            tasks = Demo.tasks()
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
            await reload()
        } catch {
            self.error = "Couldn't open that folder: \(error.localizedDescription)"
        }
    }

    /// Back to the sample board.
    func useDemo() async {
        FolderAccess.forget()
        source = .demo
        await reload()
    }
}

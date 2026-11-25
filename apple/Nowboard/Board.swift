// The board's data: categories, demo tasks, and the lists the board shows.
// Pure rules only (no SwiftUI, no files), like src/board.ts.

import Foundation
import NowboardKit

/// A category: a name and a colour. `id` is what task files store in `area:`.
struct Category: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var name: String
    var color: Palette

    /// Defaults, as in the browser demo. On a Mac the first launch copies the
    /// Tauri app's categories instead (Settings.swift).
    static let defaults = [
        Category(id: "personal", name: "Personal", color: .rose),
        Category(id: "work", name: "Work", color: .blue),
        Category(id: "freelance", name: "Freelance", color: .amber),
    ]
}

/// To and from the way `.nowboard.json` stores a category (spec 7).
extension Category {
    init(_ record: CategoryRecord) {
        self.init(id: record.id, name: record.name, color: Palette(rawValue: record.color) ?? .slate)
    }

    var record: CategoryRecord { CategoryRecord(id: id, name: name, color: color.rawValue) }
}

/// At most six categories (DESIGN.md, Settings).
let maxCategories = 6

/// A new category for the settings: "New category", the first colour nobody
/// uses yet, and a free id (`category`, `category-2`…), like useSettings.ts.
func newCategory(after cats: [Category]) -> Category {
    let used = Set(cats.map(\.color))
    var id = "category", n = 2
    while cats.contains(where: { $0.id == id }) {
        id = "category-\(n)"
        n += 1
    }
    return Category(id: id, name: "New category", color: Palette.allCases.first { !used.contains($0) } ?? .slate)
}

/// The Tasks folder as the daily-note query names it: relative to the vault
/// (the nearest folder above it with an `.obsidian` folder), e.g.
/// `Notes/Tasks`. Without a vault in sight, just the folder's own name.
func vaultRelativePath(of folder: URL) -> String {
    let parts = folder.standardizedFileURL.pathComponents
    var root = folder.standardizedFileURL
    for depth in stride(from: parts.count - 1, through: 1, by: -1) {
        root.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(".obsidian").path) {
            return parts.suffix(parts.count - depth).joined(separator: "/")
        }
    }
    return folder.lastPathComponent
}

/// Where a folder or file is, as Finder and Files name it: "iCloud Drive ›
/// vault › Tasks" instead of /private/var/mobile/Library/Mobile Documents/….
func displayLocation(of url: URL) -> String {
    // Without symlinks, so /private/var and /var compare equal; minus the leading "/".
    var parts = Array(url.resolvingSymlinksInPath().pathComponents.dropFirst())
    let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().pathComponents.dropFirst()
    // On the iPhone, "home" is the app's own folder; Files shows its Documents there.
    #if os(iOS)
        let homeName = ["On My iPhone", "Nowboard"]
    #else
        let homeName = ["Home"]
    #endif
    if let i = parts.firstIndex(of: "Mobile Documents"), i + 1 < parts.count {
        // com~apple~CloudDocs is iCloud Drive itself; iCloud~md~obsidian is an
        // app's folder in it (named after the app, files under Documents).
        let box = parts[i + 1]
        var rest = Array(parts[(i + 2)...])
        if box == "com~apple~CloudDocs" {
            parts = ["iCloud Drive"] + rest
        } else {
            if rest.first == "Documents" { rest.removeFirst() }
            let app = box.split(separator: "~").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? box
            parts = ["iCloud Drive", app] + rest
        }
    } else if let i = parts.firstIndex(of: "File Provider Storage") {
        parts = ["On My iPhone"] + parts[(i + 1)...]
    } else if parts.starts(with: home) {
        var rest = Array(parts.dropFirst(home.count))
        #if os(iOS)
            if rest.first == "Documents" { rest.removeFirst() }
        #endif
        parts = homeName + rest
    } else if parts.first == "Volumes" {
        parts.removeFirst()
    }
    return parts.joined(separator: " › ")
}

/// A Dataview query for a daily note named YYYY-MM-DD: the tasks finished
/// that day (ADR 0003). Same text as the Tauri app's settings.
func doneQuery(tasksFolder: String) -> String {
    """
    ```dataview
    LIST FROM "\(tasksFolder)"
    WHERE status = "done" AND dateformat(default(done, file.mtime), "yyyy-MM-dd") = this.file.name
    SORT default(done, file.mtime) ASC
    ```
    """
}

/// Top-left corner for a menu opened at the pointer: down and right of it,
/// flipped up or left when it wouldn't fit, never closer than 8pt to the
/// window's edges (placeMenu in cardMenu.ts).
func placeMenu(at p: CGPoint, size: CGSize, in window: CGSize) -> CGPoint {
    let edge: CGFloat = 8
    let x = p.x + size.width + edge <= window.width ? p.x : p.x - size.width
    let y = p.y + size.height + edge <= window.height ? p.y : p.y - size.height
    return CGPoint(x: max(edge, min(x, window.width - size.width - edge)),
                   y: max(edge, min(y, window.height - size.height - edge)))
}

/// The category for an `area:` id. An unknown id shows as the first category
/// (DESIGN.md: deleting a category doesn't touch task files).
func category(for area: String, in categories: [Category]) -> Category {
    categories.first { $0.id == area } ?? categories.first ?? Category.defaults[0]
}

/// A deleted task that Undo can still bring back: the task, and its file's
/// text as it was (nil on the demo board, or if it couldn't be read).
struct Deleted: Equatable {
    let task: BoardTask
    let text: String?
    /// Tells two deletes of the same task apart.
    let token = UUID()
}

/// Tasks someone else finished (Obsidian, an agent, the other device): on the
/// board before (Today or Backlog), done in the folder now. They play the same
/// finish animation as a card you tick (DESIGN.md, "Other writers exist").
func finishedElsewhere(before: [BoardTask], after: [BoardTask]) -> [String] {
    let was = Dictionary(before.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
    return after.filter { $0.status == .done && (was[$0.id] == .today || was[$0.id] == .backlog) }.map(\.id)
}

// MARK: - Demo data

/// The same sample board as the browser demo (src/api.ts), so both apps can be
/// compared side by side. Shown until you pick a Tasks folder.
enum Demo {
    static func tasks(now: Date = .now) -> [BoardTask] {
        let stamp = TaskFormat.timestamp(now)
        let earlier = TaskFormat.timestamp(now.addingTimeInterval(-2 * 3600))
        func t(_ title: String, _ area: String, _ status: TaskStatus, _ order: Double, focus: Bool = false,
               done: String? = nil, isPrivate: Bool = false, items: [ChecklistItem] = [], notes: String = "") -> BoardTask {
            BoardTask(id: TaskFormat.stem(for: title) + ".md", title: title, status: status, area: area, focus: focus, order: order,
                      created: stamp, done: status == .done ? (done ?? stamp) : nil, isPrivate: isPrivate, items: items, notes: notes)
        }
        return [
            t("Review PR for alert thresholds", "work", .today, 1024, focus: true,
              items: [.init(text: "Read the diff", done: true), .init(text: "Run it locally", done: false), .init(text: "Leave comments", done: false)],
              notes: "Check the hysteresis values against the old dashboard before approving."),
            t("Homepage copy review", "freelance", .today, 2048),
            t("Piano practice", "personal", .today, 3072, isPrivate: true),
            t("Prep notes for 1-on-1", "work", .today, 4096),
            t("Send November invoice", "freelance", .today, 5120),
            t("Write ADR on the message broker", "work", .backlog, 1024),
            t("Fix the bike brakes", "personal", .backlog, 2048),
            t("Draft portfolio essay", "freelance", .backlog, 3072),
            t("Plan Saturday", "personal", .backlog, 4096),
            t("Update sprint board", "work", .backlog, 5120),
            t("Rust book, chapter 4", "personal", .backlog, 6144),
            t("New invoice template", "freelance", .backlog, 7168),
            t("Team retro format ideas", "work", .backlog, 8192),
            t("Reply to the recruiter thread", "work", .suggested, 1024),
            t("Book train tickets", "personal", .done, 1024, done: earlier),
            t("Fix flaky e2e test", "work", .done, 2048),
        ]
    }
}

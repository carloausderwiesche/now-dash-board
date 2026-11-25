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

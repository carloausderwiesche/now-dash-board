// Every board action, end to end: the store changes the screen and writes the
// task files. Runs against a temporary folder, never a real vault.

import Foundation
import NowboardKit
import Testing

@testable import Nowboard

@MainActor
private func makeStore(_ files: [String: String] = [:]) async throws -> (BoardStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, text) in files {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let store = BoardStore(testFolder: dir)
    await store.reload()
    return (store, dir)
}

private func read(_ dir: URL, _ name: String) throws -> String {
    try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
}

@MainActor @Test func addWritesANewFileOnTop() async throws {
    let (store, dir) = try await makeStore(["Old.md": "---\nstatus: today\narea: work\norder: 100\n---\n"])
    store.add(title: "Call the dentist", area: "personal", status: .today)
    await store.waitForWrites()
    let text = try read(dir, "Call the dentist.md")
    #expect(text.contains("status: today") && text.contains("area: personal") && text.contains("order: -924"))
    #expect(store.lists.today.first?.title == "Call the dentist")
}

@MainActor @Test func completeMarksDoneAndEndsFocus() async throws {
    let (store, dir) = try await makeStore(["Buy milk.md": "---\nstatus: today\narea: personal\nfocus: true\norder: 1\n---\n"])
    store.complete("Buy milk.md")
    await store.waitForWrites()
    let text = try read(dir, "Buy milk.md")
    #expect(text.contains("status: done") && !text.contains("focus"))
    #expect(store.lists.doneToday.map(\.title) == ["Buy milk"])
}

@MainActor @Test func reopenClearsDoneAndGoesToTheTopOfToday() async throws {
    let (store, dir) = try await makeStore([
        "A.md": "---\nstatus: today\norder: 10\n---\n",
        "B.md": "---\nstatus: done\norder: 1\ndone: 2026-11-24T10:00\n---\n",
    ])
    store.reopen("B.md")
    await store.waitForWrites()
    let text = try read(dir, "B.md")
    #expect(text.contains("status: today") && text.contains("done:\n") && text.contains("order: -1014"))
}

@MainActor @Test func cycleCategoryWritesTheNextArea() async throws {
    let (store, dir) = try await makeStore(["A.md": "---\nstatus: today\narea: personal\norder: 1\n---\n"])
    store.cycleCategory("A.md")  // defaults: personal → work → freelance
    await store.waitForWrites()
    #expect(try read(dir, "A.md").contains("area: work"))
}

@MainActor @Test func onlyOneCardHasFocus() async throws {
    let (store, dir) = try await makeStore([
        "A.md": "---\nstatus: today\nfocus: true\norder: 1\n---\n",
        "B.md": "---\nstatus: today\norder: 2\n---\n",
    ])
    store.toggleFocus("B.md")
    await store.waitForWrites()
    #expect(try read(dir, "B.md").contains("focus: true"))
    #expect(!(try read(dir, "A.md").contains("focus")))
}

@MainActor @Test func moveSetsTheMidpointOrder() async throws {
    let (store, dir) = try await makeStore([
        "A.md": "---\nstatus: today\norder: 1024\n---\n",
        "B.md": "---\nstatus: today\norder: 2048\n---\n",
        "C.md": "---\nstatus: backlog\norder: 1\n---\nkeep this body\n",
    ])
    store.move("C.md", to: .today, before: "B.md")
    await store.waitForWrites()
    let text = try read(dir, "C.md")
    #expect(text.contains("status: today") && text.contains("order: 1536") && text.hasSuffix("keep this body\n"))
}

@MainActor @Test func renameMovesTheFile() async throws {
    let (store, dir) = try await makeStore(["Old.md": "---\nstatus: today\norder: 1\n---\nbody\n"])
    store.rename("Old.md", to: "Fix: token")
    await store.waitForWrites()
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Old.md").path))
    #expect(try read(dir, "Fix- token.md").contains("title: 'Fix: token'"))
    #expect(store.tasks.map(\.title) == ["Fix: token"])
}

@MainActor @Test func checklistAndNotesEditsAreSaved() async throws {
    let (store, dir) = try await makeStore(["A.md": "---\nstatus: today\norder: 1\n---\n"])
    var t = try #require(store.task("A.md"))
    t.items = [ChecklistItem(text: "step", done: true)]
    t.notes = "a note"
    store.update(t)
    await store.waitForWrites()
    #expect(try read(dir, "A.md").hasSuffix("---\n- [x] step\n\na note\n"))
}

@MainActor @Test func acceptAndDismissSuggestions() async throws {
    let (store, dir) = try await makeStore([
        "S1.md": "---\nstatus: suggested\norder: 1\nfrom: '[[Notes/x]]'\n---\n",
        "S2.md": "---\nstatus: suggested\norder: 2\n---\n",
    ])
    store.accept("S1.md")
    store.delete("S2.md")
    await store.waitForWrites()
    let text = try read(dir, "S1.md")
    #expect(text.contains("status: backlog") && text.contains("from: '[[Notes/x]]'"))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("S2.md").path))
}

@MainActor @Test func aFailedWriteShowsAnError() async throws {
    let (store, _) = try await makeStore(["Broken.md": "---\nstatus: today\narea: [work\n---\n"])
    store.complete("Broken.md")
    await store.waitForWrites()
    #expect(store.error != nil)
}

@MainActor @Test func aFileWrittenElsewhereShowsUp() async throws {
    let (store, dir) = try await makeStore(["A.md": "---\nstatus: today\norder: 1\n---\n"])
    // Like Obsidian or a sync: a plain atomic save of a new file.
    try "---\nstatus: backlog\narea: work\n---\n".write(to: dir.appendingPathComponent("From Obsidian.md"), atomically: true, encoding: .utf8)
    for _ in 0..<30 where store.task("From Obsidian.md") == nil {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(store.task("From Obsidian.md")?.status == .backlog)
}

#if os(macOS)
    import AppKit

    /// The ⌥ Space panel catches ⌘1–⌘6 itself (the app isn't active while you
    /// type into it, so SwiftUI's keyboard shortcuts wouldn't fire).
    @MainActor @Test func thePanelPassesCommandDigitsToQuickAdd() throws {
        let panel = QuickPanel()
        var picked: Int?
        panel.keys.onCommandDigit = { picked = $0 }
        let key = { (chars: String, flags: NSEvent.ModifierFlags) in
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 19)!
        }
        #expect(panel.performKeyEquivalent(with: key("2", .command)))
        #expect(picked == 2)
        picked = nil
        #expect(!panel.performKeyEquivalent(with: key("9", .command)))  // only 1–6
        #expect(!panel.performKeyEquivalent(with: key("2", [.command, .shift])))
        #expect(picked == nil)
    }
#endif

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

@MainActor @Test func finishPlaysTheAnimationThenMarksDone() async throws {
    let (store, dir) = try await makeStore(["A.md": "---\nstatus: today\norder: 1\n---\n"])
    store.drag.cardFrames["A.md"] = CGRect(x: 0, y: 0, width: 200, height: 128)  // on screen
    store.finish("A.md")
    #expect(store.finishing["A.md"]?.step == .ticked)
    #expect(store.task("A.md")?.status == .today)  // still on the board while it animates
    try await Task.sleep(for: .milliseconds(1000))
    await store.waitForWrites()
    #expect(try read(dir, "A.md").contains("status: done"))
}

@Test func onlyOpenCardsThatAreNowDoneCountAsFinishedElsewhere() {
    func t(_ id: String, _ s: TaskStatus) -> BoardTask { BoardTask(id: id, title: id, status: s, area: "work") }
    let before = [t("a", .today), t("b", .backlog), t("c", .done), t("d", .today), t("e", .suggested)]
    let after = [t("a", .done), t("b", .done), t("c", .done), t("d", .today), t("e", .done), t("new", .done)]
    #expect(finishedElsewhere(before: before, after: after) == ["a", "b"])
}

@MainActor @Test func aTaskFinishedElsewhereLandsInDoneWithoutBeingWritten() async throws {
    let (store, dir) = try await makeStore(["A.md": "---\nstatus: today\norder: 1\n---\n"])
    let done = "---\nstatus: done\norder: 1\ndone: 2026-11-25T09:00\nnote: from obsidian\n---\n"
    try done.write(to: dir.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
    for _ in 0..<30 where store.task("A.md")?.status != .done {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(store.task("A.md")?.done == "2026-11-25T09:00")
    #expect(try read(dir, "A.md") == done)
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

@MainActor @Test func undoWritesADeletedFileBackExactlyAsItWas() async throws {
    let text = "---\nstatus: backlog\norder: 3\nmood: unknown field\n---\n- [ ] step\n\nnotes   kept as typed\n"
    let (store, dir) = try await makeStore(["A.md": text])
    store.delete("A.md")
    await store.waitForWrites()
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("A.md").path))
    #expect(store.undoable?.task.id == "A.md")
    store.undoDelete()
    await store.waitForWrites()
    #expect(try read(dir, "A.md") == text)
    #expect(store.task("A.md")?.status == .backlog)
}

@MainActor @Test func undoWhileTheCardIsStillFadingKeepsTheFile() async throws {
    let (store, dir) = try await makeStore(["A.md": "---\nstatus: today\norder: 1\n---\n"])
    store.delete("A.md")
    store.undoDelete()
    await store.waitForWrites()
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("A.md").path))
    #expect(store.task("A.md") != nil && store.deleting.isEmpty)
}

@MainActor @Test func categoriesComeFromTheTasksFolder() async throws {
    let (store, _) = try await makeStore([
        ".nowboard.json": #"{"categories": [{"id": "home", "name": "Home", "color": "teal"}, {"id": "work", "name": "Job", "color": "nope"}]}"#
    ])
    #expect(store.settings.categories == [
        Category(id: "home", name: "Home", color: .teal), Category(id: "work", name: "Job", color: .slate),
    ])
}

@MainActor @Test func aMissingSettingsFileIsStartedFromThisDevicesCategories() async throws {
    let (store, dir) = try await makeStore()
    await store.waitForWrites()
    let text = try read(dir, ".nowboard.json")
    #expect(text.contains("\"personal\"") && text.contains("\"freelance\""))
    #expect(store.settings.categories == Category.defaults)
}

@MainActor @Test func editingCategoriesWritesTheFileAfterAPause() async throws {
    let (store, dir) = try await makeStore([".nowboard.json": #"{"categories": [{"id": "a", "name": "A", "color": "red"}]}"#])
    store.setCategories([Category(id: "a", name: "Al", color: .red)])
    store.setCategories([Category(id: "a", name: "Alpha", color: .red), Category(id: "b", name: "B", color: .blue)])
    await store.waitForWrites()
    let saved = try TaskFolder(url: dir).loadCategories()
    #expect(saved?.map(\.name) == ["Alpha", "B"])
}

@MainActor @Test func aBrokenSettingsFileIsReportedAndLeftAlone() async throws {
    let (store, dir) = try await makeStore([".nowboard.json": "{ broken"])
    await store.waitForWrites()
    #expect(store.error?.contains(".nowboard.json") == true)
    #expect(try read(dir, ".nowboard.json") == "{ broken")
}

@Test func aNewCategoryGetsAFreeIdAndAnUnusedColour() {
    let cats = [Category(id: "category", name: "A", color: .rose), Category(id: "category-2", name: "B", color: .red)]
    let new = newCategory(after: cats)
    #expect(new.id == "category-3" && new.color == .orange && new.name == "New category")
}

@Test func theDailyNoteQueryNamesTheTasksFolderRelativeToTheVault() throws {
    let vault = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
    let tasks = vault.appendingPathComponent("Notes/Tasks")
    try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
    #expect(vaultRelativePath(of: tasks) == "Tasks")  // no vault found: just the name
    try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
    #expect(vaultRelativePath(of: tasks) == "Notes/Tasks")
    #expect(doneQuery(tasksFolder: "Notes/Tasks").contains(#"LIST FROM "Notes/Tasks""#))
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

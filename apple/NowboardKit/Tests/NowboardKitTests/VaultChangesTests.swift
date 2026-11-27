// Changing notes: history, log, undo, and everything the engine must refuse.
// Only temporary vaults; never a real one.

import Foundation
import Testing

@testable import NowboardKit

private let t0 = ISO8601DateFormatter().date(from: "2026-11-27T09:45:12Z")!

private func makeVault(_ files: [String: String] = [:]) throws -> (VaultChanges, URL) {
    let vault = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-tidy-\(UUID().uuidString)")
    for dir in [".obsidian", "Notes/Tasks", "Notes/Inbox", "Wiki/Ideas", "Wiki/Projects", "Archive"] {
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(dir), withIntermediateDirectories: true)
    }
    for (path, text) in files {
        let url = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    return (VaultChanges(config: VaultConfig(vault: vault), now: { t0 }), vault)
}

private func read(_ vault: URL, _ path: String) -> String? { try? String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8) }
private func exists(_ vault: URL, _ path: String) -> Bool { FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path) }

private func op(_ kind: VaultOperation.Kind, _ path: String, to: String? = nil, name: String? = nil, text: String? = nil, title: String? = nil) -> VaultOperation {
    VaultOperation(kind: kind, path: path, to: to, name: name, text: text, title: title)
}

// MARK: - Move

@Test func aMoveKeepsTheOriginalInTheHistoryAndUpdatesLinks() throws {
    let (changes, vault) = try makeVault([
        "Notes/Inbox/Plan.md": "# Plan\nSee [[Plan]] itself.\n",
        "Wiki/Ideas/Idea.md": "Based on [[Notes/Inbox/Plan|the plan]] and [[Other]].\n",
        "Wiki/Other.md": "no links\n",
    ])
    defer { try? FileManager.default.removeItem(at: vault) }
    let record = try changes.apply(op(.move, "Notes/Inbox/Plan.md", to: "Wiki/Projects/Plan.md"))

    #expect(!exists(vault, "Notes/Inbox/Plan.md"))
    #expect(read(vault, "Wiki/Projects/Plan.md") == "# Plan\nSee [[Plan]] itself.\n")  // the plain link still works
    #expect(read(vault, "Wiki/Ideas/Idea.md") == "Based on [[Wiki/Projects/Plan|the plan]] and [[Other]].\n")
    #expect(record.linksChanged == 1 && record.from == "Notes/Inbox/Plan.md")
    // The originals are kept.
    #expect(read(vault, ".nowboard/history/\(record.id)/Notes/Inbox/Plan.md") == "# Plan\nSee [[Plan]] itself.\n")
    #expect(read(vault, ".nowboard/history/\(record.id)/Wiki/Ideas/Idea.md") == "Based on [[Notes/Inbox/Plan|the plan]] and [[Other]].\n")
    // The log has one line, and it's the change.
    #expect(changes.records().map(\.id) == [record.id])
}

@Test func aRenameChangesTheNameLinksFollow() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "own [[Plan]]\n", "Wiki/Ideas/A.md": "[[Plan]] [[Wiki/Plan#Goals]]\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    try changes.apply(op(.rename, "Wiki/Plan.md", name: "Roadmap"))
    #expect(read(vault, "Wiki/Roadmap.md") == "own [[Roadmap]]\n")
    #expect(read(vault, "Wiki/Ideas/A.md") == "[[Roadmap]] [[Wiki/Roadmap#Goals]]\n")
    #expect(!exists(vault, "Wiki/Plan.md"))
}

@Test func aRenameUsesTheSameFileNameRulesAsTaskTitles() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    try changes.apply(op(.rename, "Wiki/Plan.md", name: "A/B: C?"))
    #expect(exists(vault, "Wiki/A-B- C-.md"))
}

@Test func aMoveIntoANewFolderCreatesIt() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    try changes.apply(op(.move, "Wiki/Plan.md", to: "Wiki/New/Deeper/Plan.md"))
    #expect(read(vault, "Wiki/New/Deeper/Plan.md") == "x\n")
}

@Test func twoNotesWithTheSameNameKeepTheirOwnLinks() throws {
    let (changes, vault) = try makeVault([
        "Wiki/A/Plan.md": "a\n", "Wiki/B/Plan.md": "b\n", "Wiki/Index.md": "[[Wiki/A/Plan]] [[Wiki/B/Plan]] [[Plan]]\n",
    ])
    defer { try? FileManager.default.removeItem(at: vault) }
    let record = try changes.apply(op(.rename, "Wiki/A/Plan.md", name: "Roadmap"))
    #expect(read(vault, "Wiki/Index.md") == "[[Wiki/A/Roadmap]] [[Wiki/B/Plan]] [[Plan]]\n")
    #expect(record.linksAmbiguous == 1)  // the plain `[[Plan]]` could mean either: left alone
}

// MARK: - Refusals

@Test func aMoveNeverOverwritesAnExistingNote() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "mine\n", "Archive/Plan.md": "other\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    #expect(changes.problem(with: op(.move, "Wiki/Plan.md", to: "Archive/Plan.md"))?.contains("already exists") == true)
    #expect(throws: ChangeError.self) { try changes.apply(op(.move, "Wiki/Plan.md", to: "Archive/Plan.md")) }
    #expect(read(vault, "Archive/Plan.md") == "other\n" && read(vault, "Wiki/Plan.md") == "mine\n")
    // Same name in other capitals counts as existing (a Mac doesn't tell them apart).
    #expect(changes.problem(with: op(.move, "Wiki/Plan.md", to: "Archive/PLAN.md")) != nil)
    #expect(changes.records().isEmpty)  // refused: nothing logged
}

@Test(arguments: [
    "../Secrets.md", "/etc/passwd.md", ".obsidian/app.md", ".nowboard/changes.jsonl.md", "Wiki/.hidden.md", "Notes/Tasks/Task.md",
    "notes/TASKS/Task.md", "Wiki/Plan.txt", "Wiki//Plan.md", "Wiki\\Plan.md", "", "Wiki/Plan.md/../x.md", "~/x.md",
])
func pathsThatAreNotAllowedAreRefusedAsSourceAndDestination(path: String) throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n", "Notes/Tasks/Task.md": "---\nstatus: today\n---\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    #expect(changes.problem(with: op(.move, path, to: "Wiki/Ok.md")) != nil)
    #expect(changes.problem(with: op(.move, "Wiki/Plan.md", to: path)) != nil)
    #expect(changes.problem(with: op(.append, path, text: "hi")) != nil)
    #expect(changes.records().isEmpty)
    #expect(exists(vault, "Wiki/Plan.md"))
}

@Test func theVaultGuideAndSavedCapturesAreNeverChanged() throws {
    let raw = "---\ncaptured: 2026-11-26T13:05\n---\ntyped text"
    let (changes, vault) = try makeVault(["_vault-guide.md": "guide\n", "Notes/Inbox/2026-11-26 13-05-22.md": raw, "Wiki/Plan.md": "x\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    #expect(changes.problem(with: op(.append, "_vault-guide.md", text: "x")) != nil)
    #expect(changes.problem(with: op(.move, "Wiki/Plan.md", to: "_vault-guide.md")) != nil)
    #expect(changes.problem(with: op(.move, "Notes/Inbox/2026-11-26 13-05-22.md", to: "Wiki/Raw.md"))?.contains("saved capture") == true)
    #expect(changes.problem(with: op(.append, "Notes/Inbox/2026-11-26 13-05-22.md", text: "x"))?.contains("saved capture") == true)
    #expect(changes.problem(with: op(.retitle, "Notes/Inbox/2026-11-26 13-05-22.md", title: "x")) != nil)
    #expect(read(vault, "Notes/Inbox/2026-11-26 13-05-22.md") == raw)
}

@Test func aNoteThatIsFiledInTheInboxCanBeMovedOut() throws {
    let (changes, vault) = try makeVault(["Notes/Inbox/Idea.md": "---\nfrom: '[[Notes/Inbox/2026-11-26 13-05-22]]'\n---\ntext\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    #expect(changes.problem(with: op(.move, "Notes/Inbox/Idea.md", to: "Wiki/Ideas/Idea.md")) == nil)
}

@Test func aMissingNoteOrOddRequestIsRefused() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "# Plan\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    #expect(changes.problem(with: op(.move, "Wiki/Nope.md", to: "Wiki/X.md")) != nil)
    #expect(changes.problem(with: op(.move, "Wiki/Plan.md")) != nil)  // no destination
    #expect(changes.problem(with: op(.move, "Wiki/Plan.md", to: "Wiki/Plan.md")) != nil)  // already there
    #expect(changes.problem(with: op(.rename, "Wiki/Plan.md")) != nil)
    #expect(changes.problem(with: op(.rename, "Wiki/Plan.md", name: "plan")) != nil)  // only capitals differ
    #expect(changes.problem(with: op(.append, "Wiki/Plan.md", text: "  \n ")) != nil)
    #expect(changes.problem(with: op(.append, "Wiki/Plan.md", text: String(repeating: "x", count: 5000))) != nil)
    #expect(changes.problem(with: op(.retitle, "Wiki/Plan.md", title: "")) != nil)
    #expect(changes.problem(with: op(.retitle, "Wiki/Plan.md", title: "a\nb")) != nil)
}

@Test func aLinkOutOfTheVaultIsNotFollowed() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    let outside = vault.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("Linked"), withDestinationURL: outside)
    #expect(changes.problem(with: op(.move, "Wiki/Plan.md", to: "Linked/Plan.md")) != nil)
    #expect(exists(vault, "Wiki/Plan.md"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}

@Test func thereIsNoWayToDeleteOrEmptyANote() throws {
    // The operation kinds are the whole list.
    #expect(VaultOperation.Kind.allCases.map(\.rawValue).sorted() == ["append", "move", "rename", "retitle"])
    let json = #"{"operations":[{"op":"delete","path":"Wiki/Plan.md"},{"op":"remove","path":"x.md"},{"op":"empty","path":"x.md"},{"op":"append","path":"Wiki/Plan.md","text":"ok"}]}"#
    let (ops, dropped) = try VaultOperation.decodeList(Data(json.utf8))
    #expect(ops.count == 1 && ops[0].kind == .append)
    #expect(dropped == 3)
}

// MARK: - Append and retitle

@Test func appendAddsAtTheEndAndKeepsTheOriginal() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "# Plan\nline"])  // no final line break
    defer { try? FileManager.default.removeItem(at: vault) }
    let record = try changes.apply(op(.append, "Wiki/Plan.md", text: "- more\n"))
    #expect(read(vault, "Wiki/Plan.md") == "# Plan\nline\n\n- more\n")
    #expect(read(vault, ".nowboard/history/\(record.id)/Wiki/Plan.md") == "# Plan\nline")
}

@Test func retitleChangesOnlyTheFirstHeading() throws {
    let text = "---\ntitle: x\n# not a heading (frontmatter)\n---\n```\n# in code\n```\n# Old title\ntext\n# Second\n"
    let (changes, vault) = try makeVault(["Wiki/Plan.md": text])
    defer { try? FileManager.default.removeItem(at: vault) }
    try changes.apply(op(.retitle, "Wiki/Plan.md", title: "New title"))
    #expect(read(vault, "Wiki/Plan.md") == "---\ntitle: x\n# not a heading (frontmatter)\n---\n```\n# in code\n```\n# New title\ntext\n# Second\n")
}

@Test func retitleKeepsWindowsLineBreaksAndNeedsAHeading() throws {
    let (changes, vault) = try makeVault(["Wiki/A.md": "# Old\r\ntext\r\n", "Wiki/B.md": "no heading\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    try changes.apply(op(.retitle, "Wiki/A.md", title: "New"))
    #expect(read(vault, "Wiki/A.md") == "# New\r\ntext\r\n")
    #expect(changes.problem(with: op(.retitle, "Wiki/B.md", title: "New"))?.contains("no first heading") == true)
}

// MARK: - Undo

@Test func undoPutsEverythingBackFromTheHistory() throws {
    let (changes, vault) = try makeVault([
        "Notes/Inbox/Plan.md": "# Plan\nSee [[Plan]].\n", "Wiki/Ideas/Idea.md": "[[Notes/Inbox/Plan]] and\r\n[[Other]]",
    ])
    defer { try? FileManager.default.removeItem(at: vault) }
    let record = try changes.apply(op(.move, "Notes/Inbox/Plan.md", to: "Wiki/Projects/Plan.md"))
    #expect(read(vault, "Wiki/Ideas/Idea.md") != "[[Notes/Inbox/Plan]] and\r\n[[Other]]")
    let undone = try changes.undo(record.id)
    #expect(undone.undone)
    #expect(read(vault, "Notes/Inbox/Plan.md") == "# Plan\nSee [[Plan]].\n")
    #expect(read(vault, "Wiki/Ideas/Idea.md") == "[[Notes/Inbox/Plan]] and\r\n[[Other]]")  // byte for byte, CRLF included
    #expect(!exists(vault, "Wiki/Projects/Plan.md"))
    #expect(changes.records().first?.undone == true)
    // The history is kept even after the undo.
    #expect(exists(vault, ".nowboard/history/\(record.id)/Notes/Inbox/Plan.md"))
    // Twice isn't possible.
    #expect(throws: ChangeError.alreadyUndone(record.id)) { try changes.undo(record.id) }
}

@Test func undoRefusesIfTheMovedNoteWasEditedAfterwards() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n", "Wiki/Other.md": "[[Plan]] [[Wiki/Plan]]\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    let record = try changes.apply(op(.move, "Wiki/Plan.md", to: "Archive/Plan.md"))
    try "x\nmy new work\n".write(to: vault.appendingPathComponent("Archive/Plan.md"), atomically: true, encoding: .utf8)
    #expect(throws: ChangeError.changedSince("Archive/Plan.md")) { try changes.undo(record.id) }
    // Nothing was changed by the refused undo.
    #expect(read(vault, "Archive/Plan.md") == "x\nmy new work\n")
    #expect(read(vault, "Wiki/Other.md") == "[[Plan]] [[Archive/Plan]]\n")
    #expect(changes.records().first?.undone == false)
}

@Test func undoRefusesIfALinkingNoteWasEditedAfterwards() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n", "Wiki/Other.md": "[[Wiki/Plan]]\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    let record = try changes.apply(op(.move, "Wiki/Plan.md", to: "Archive/Plan.md"))
    try "[[Archive/Plan]] I added this\n".write(to: vault.appendingPathComponent("Wiki/Other.md"), atomically: true, encoding: .utf8)
    #expect(throws: ChangeError.changedSince("Wiki/Other.md")) { try changes.undo(record.id) }
    #expect(exists(vault, "Archive/Plan.md") && !exists(vault, "Wiki/Plan.md"))
}

@Test func undoRefusesIfTheOldPathIsTakenAgain() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    let record = try changes.apply(op(.move, "Wiki/Plan.md", to: "Archive/Plan.md"))
    try "new note on the old path\n".write(to: vault.appendingPathComponent("Wiki/Plan.md"), atomically: true, encoding: .utf8)
    #expect(throws: ChangeError.self) { try changes.undo(record.id) }
    #expect(read(vault, "Wiki/Plan.md") == "new note on the old path\n")  // never overwritten
}

@Test func undoOfAnAppendAndARetitle() throws {
    let (changes, vault) = try makeVault(["Wiki/A.md": "# A\nx\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    let first = try changes.apply(op(.append, "Wiki/A.md", text: "added"))
    let second = try changes.apply(op(.retitle, "Wiki/A.md", title: "B"))
    // The second change depends on the first: undoing the first now would lose the second, so it's refused.
    #expect(throws: ChangeError.changedSince("Wiki/A.md")) { try changes.undo(first.id) }
    try changes.undo(second.id)
    try changes.undo(first.id)
    #expect(read(vault, "Wiki/A.md") == "# A\nx\n")
}

@Test func undoOnlyTakesWellFormedIdsAndKnownChanges() throws {
    let (changes, vault) = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    for id in ["", "../../etc", "20261127-094512-zzzz", "nope", "20261127-094512"] {
        #expect(throws: ChangeError.unknownChange(id)) { try changes.undo(id) }
    }
    #expect(throws: ChangeError.unknownChange("20261127-094512-abcd")) { try changes.undo("20261127-094512-abcd") }
}

// MARK: - The log and the history

@Test func theLogOnlyGrowsAndEveryLineIsJson() throws {
    let (changes, vault) = try makeVault(["Wiki/A.md": "x\n", "Wiki/B.md": "y\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    let one = try changes.apply(op(.append, "Wiki/A.md", text: "1"))
    let log1 = try #require(read(vault, ".nowboard/changes.jsonl"))
    let two = try changes.apply(op(.append, "Wiki/B.md", text: "2"))
    try changes.undo(one.id)
    let log3 = try #require(read(vault, ".nowboard/changes.jsonl"))
    #expect(log3.hasPrefix(log1))  // earlier lines are never rewritten
    #expect(log3.split(separator: "\n").count == 3)  // change, change, undo
    for line in log3.split(separator: "\n") { #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil) }
    #expect(changes.records().map(\.id) == [two.id, one.id])  // newest first
}

@Test func theHistoryIsCreateOnlyAndUniquePerChange() throws {
    let (changes, vault) = try makeVault(["Wiki/A.md": "x\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    let first = try changes.apply(op(.append, "Wiki/A.md", text: "1"))
    let second = try changes.apply(op(.append, "Wiki/A.md", text: "2"))
    #expect(first.id != second.id)  // two changes in the same second still have their own folder
    #expect(read(vault, ".nowboard/history/\(first.id)/Wiki/A.md") == "x\n")
    #expect(read(vault, ".nowboard/history/\(second.id)/Wiki/A.md") == "x\n\n1\n")
}

@Test func theHiddenFolderIsNotPartOfTheVaultsNotes() throws {
    let (changes, vault) = try makeVault(["Wiki/A.md": "x\n"])
    defer { try? FileManager.default.removeItem(at: vault) }
    try changes.apply(op(.append, "Wiki/A.md", text: "1"))
    #expect(changes.allNotes() == ["Wiki/A.md"])  // the history copy under .nowboard doesn't count
}

@Test func aFailureHalfWayPutsEverythingBack() throws {
    let (changes, vault) = try makeVault(["Wiki/Plan.md": "x\n", "Locked/Other.md": "[[Wiki/Plan]]\n"])
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vault.appendingPathComponent("Locked").path)
        try? FileManager.default.removeItem(at: vault)
    }
    // The folder of the linking note can't be written to: updating its links fails after the move.
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: vault.appendingPathComponent("Locked").path)
    #expect(throws: ChangeError.self) { try changes.apply(op(.move, "Wiki/Plan.md", to: "Archive/Plan.md")) }
    #expect(read(vault, "Wiki/Plan.md") == "x\n")  // back where it was
    #expect(!exists(vault, "Archive/Plan.md"))
    #expect(read(vault, "Locked/Other.md") == "[[Wiki/Plan]]\n")
    #expect(changes.records().isEmpty)
}

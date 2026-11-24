// Swift-only details the shared fixtures don't reach: how we quote the
// strings we write, and the byte-level splitting.

import Foundation
import Testing
import Yams

@testable import NowboardKit

@Test("strings that YAML would misread get quotes, others stay plain", arguments: [
    ("work", "k: work\n"),
    ("true", "k: 'true'\n"),
    ("2026", "k: '2026'\n"),
    ("null", "k: 'null'\n"),
    ("Fix: token", "k: 'Fix: token'\n"),
    ("[[Wiki/X]]", "k: '[[Wiki/X]]'\n"),
    ("2026-11-22T09:40", "k: 2026-11-22T09:40\n"),
    ("Café crème", "k: Café crème\n"),
    (" padded", "k: ' padded'\n"),
])
func quoting(value: String, yaml: String) throws {
    var fm = Frontmatter()
    fm.set("k", stringNode(value))
    let written = try fm.render()
    #expect(written == yaml)
    // And it reads back as exactly the same text.
    #expect(fieldText(try Frontmatter.parse(written)["k"]) == value)
}

@Test func numbersAreWrittenLikeRust() {
    #expect(numberText(-1024) == "-1024")
    #expect(numberText(1024.5) == "1024.5")
    #expect(numberText(0.1 + 0.2) == "0.30000000000000004")
}

@Test func yesIsNotABooleanAndDatesStayText() throws {
    let fm = try Frontmatter.parse("focus: yes\ndone: 2026-11-22\norder: 0x10\n")
    #expect(TaskFormat.parse(id: "A.md", text: "---\nfocus: yes\n---\n").focus == false)
    #expect(fieldText(fm["done"]) == "2026-11-22")
    #expect(TaskFormat.parse(id: "A.md", text: "---\norder: 0x10\n---\n").order == 16)
}

@Test func duplicateKeysAreInvalid() {
    // Like Rust: a key twice is invalid YAML, so saving such a file is refused.
    #expect(throws: FrontmatterError.self) {
        try Frontmatter.parse("status: today\nstatus: done\n")
    }
}

@Test func splittingWorksOnBytes() {
    #expect(splitFrontmatter("---\n---\nbody").yaml == "")
    #expect(splitFrontmatter("---\na: 1\n---\nbody").body == "body")
    #expect(splitFrontmatter("---\r\na: 1\r\n---\r\nbody\r\n").body == "body\r\n")
    #expect(splitFrontmatter("---\nno end").yaml == nil)
    #expect(splitFrontmatter("text\n---\na: 1\n---\n").yaml == nil)
}

@Test func linesLikeRust() {
    #expect(TaskFormat.lines(of: "a\r\nb\n") == ["a", "b"])
    #expect(TaskFormat.lines(of: "a\n\nb") == ["a", "", "b"])
    #expect(TaskFormat.lines(of: "") == [])
}

@Test func refusesPathsOutsideTheFolder() {
    let folder = TaskFolder(url: URL(fileURLWithPath: "/vault/Notes/Tasks"))
    for bad in ["../secret.md", "/etc/passwd.md", "sub/x.md", ".hidden.md", "README.md", ""] {
        #expect(throws: TaskFileError.notATaskFile(bad)) { try folder.path(of: bad) }
    }
    #expect((try? folder.path(of: "Fix it.md")) != nil)
}

@Test func completingWritesOnlyItsOwnFile() throws {
    let vault = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-complete-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: vault) }
    let tasks = vault.appendingPathComponent("Notes/Tasks")
    let daily = vault.appendingPathComponent("Daily")
    try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: daily, withIntermediateDirectories: true)
    try "---\nstatus: today\nfocus: true\n---\n".write(to: tasks.appendingPathComponent("Buy milk.md"), atomically: false, encoding: .utf8)
    let note = daily.appendingPathComponent("2026-11-22.md")
    try "# Sunday\nhalf a thought".write(to: note, atomically: false, encoding: .utf8)

    let t = try TaskFolder(url: tasks).complete("Buy milk.md", now: "2026-11-22T10:40")
    #expect(t.status == .done && !t.focus && t.done == "2026-11-22T10:40")
    #expect(try String(contentsOf: note, encoding: .utf8) == "# Sunday\nhalf a thought")
}

@Test func timestampsAreLocalMinutes() {
    let utc = TimeZone(identifier: "UTC")!
    #expect(TaskFormat.timestamp(Date(timeIntervalSince1970: 0), timeZone: utc) == "1970-01-01T00:00")
}

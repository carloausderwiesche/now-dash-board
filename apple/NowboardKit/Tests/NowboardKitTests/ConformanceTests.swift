// Runs the shared conformance cases in fixtures/task-format/, the same ones
// `cargo test` runs for the Tauri app. What a case looks like:
// fixtures/task-format/README.md.
//
// Swift note: this uses Swift Testing. `@Test` marks a test; with
// `arguments:` it runs once per value, and each run is reported on its own,
// so a failing fixture shows up by name. `#expect` checks a condition and
// carries on; `#require` stops the test if it fails.

import Foundation
import Testing
import Yams

@testable import NowboardKit

/// `fixtures/task-format`, found from this file's own path:
/// apple/NowboardKit/Tests/NowboardKitTests/ConformanceTests.swift → four folders up is the repo.
let fixtures: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("fixtures/task-format")
}()

/// The names of all cases, e.g. `08-keeps-unknown-fields-and-body`.
let caseNames: [String] = {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []
    return files.compactMap { $0.hasSuffix(".expected.json") ? String($0.dropLast(".expected.json".count)) : nil }
        .filter { $0 != "folder" }
        .sorted()
}()

private func json(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func read(_ name: String) -> String? {
    try? String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
}

/// A task in the fixtures' JSON shape (the file format's own field names).
private func asJSON(_ t: BoardTask) -> [String: Any] {
    [
        "title": t.title, "status": t.status.rawValue, "area": t.area, "focus": t.focus,
        "order": t.order.map { $0 as Any } ?? NSNull(),
        "created": t.created ?? NSNull(), "done": t.done ?? NSNull(),
        "project": t.project ?? NSNull(), "from": t.from ?? NSNull(),
        "private": t.isPrivate,
        "items": t.items.map { ["text": $0.text, "done": $0.done] },
        "notes": t.notes,
    ]
}

/// Sorted, readable JSON for error messages.
private func pretty(_ value: Any) -> String {
    let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\(value)"
}

/// Applies a case's `save`/`new` changes to a task.
private func apply(_ changes: [String: Any], to t: inout BoardTask) {
    for (key, value) in changes {
        switch key {
        case "title": t.title = value as! String
        case "status": t.status = TaskStatus(rawValue: value as! String)!
        case "area": t.area = value as! String
        case "focus": t.focus = value as! Bool
        case "order": t.order = (value as! NSNumber).doubleValue
        case "created": t.created = value as? String
        case "done": t.done = value as? String
        case "project": t.project = value as? String
        case "from": t.from = value as? String
        case "notes": t.notes = value as! String
        case "items":
            t.items = (value as! [[String: Any]]).map { ChecklistItem(text: $0["text"] as! String, done: $0["done"] as! Bool) }
        default: Issue.record("unknown field in fixture: \(key)")
        }
    }
}

/// What a YAML value *means*, ignoring how it's quoted: `'[[X]]'` and `"[[X]]"` are equal.
private func meaning(_ node: Node) -> String {
    switch node {
    case .scalar(let s): "\(YAMLValue(s))"
    case .mapping(let m): "{" + m.map { "\(meaning($0.key)): \(meaning($0.value))" }.joined(separator: ", ") + "}"
    case .sequence(let s): "[" + s.map(meaning).joined(separator: ", ") + "]"
    case .alias: "alias"
    }
}

/// The spec's "kept": same keys, same order, same values; body byte-for-byte.
private func expectSameFile(_ name: String, actual: String, expected: String) throws {
    #expect(actual.hasPrefix("---\n"), "\(name): a written file starts with ---")
    let (ay, ab) = splitFrontmatter(actual)
    let (ey, eb) = splitFrontmatter(expected)
    let a = try Frontmatter.parse(ay ?? ""), e = try Frontmatter.parse(ey ?? "")
    let fields = { (f: Frontmatter) in f.fields.map { "\(meaning($0.key)) = \(meaning($0.value))" } }
    #expect(fields(a) == fields(e), "\(name): frontmatter\n--- written:\n\(actual)")
    #expect(ab == eb, "\(name): body must match byte-for-byte")
}

@Test("every file in the fixture folder belongs to a case")
func noOrphanFixtures() throws {
    #expect(caseNames.count >= 20)
    for file in try FileManager.default.contentsOfDirectory(atPath: fixtures.path) {
        for suffix in [".input.md", ".after-save.md"] where file.hasSuffix(suffix) {
            #expect(caseNames.contains(String(file.dropLast(suffix.count))), "\(file) has no .expected.json")
        }
    }
}

@Test("fixture case", arguments: caseNames)
func fixtureCase(_ name: String) throws {
    let spec = try json("\(name).expected.json")
    let file = try #require(spec["file"] as? String)
    let input = read("\(name).input.md")

    // Reading, like loadAll when it's the only file in the folder.
    var loaded = input.map { TaskFormat.parse(id: file, text: $0) }
    if var t = loaded, t.status == .done {
        t.done = TaskFormat.doneTime(t.done, modified: spec["modified"] as? String)
        loaded = t
    }
    if let expected = spec["task"] as? [String: Any] {
        let actual = asJSON(try #require(loaded, "a `task` case needs an input file"))
        #expect(NSDictionary(dictionary: actual).isEqual(to: expected), "\(name): parsed\n\(pretty(actual))\nexpected\n\(pretty(expected))")
    }

    // Writing.
    let after = read("\(name).after-save.md")
    let saveError = spec["save_error"] as? Bool == true
    let writes = spec["save"] != nil || spec["new"] != nil || spec["rename"] != nil
    #expect(writes == (after != nil || saveError), "\(name): .after-save.md and save/new/rename go together")
    guard writes else { return }

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-fixture-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // `defer` runs when the function ends, however it ends: the folder is always cleaned up.
    defer { try? FileManager.default.removeItem(at: dir) }
    let folder = TaskFolder(url: dir)
    let existing = spec["existing"] as? [String] ?? []
    for other in existing {
        try "x".write(to: dir.appendingPathComponent(other), atomically: false, encoding: .utf8)
    }
    if let input {
        try input.write(to: dir.appendingPathComponent(file), atomically: false, encoding: .utf8)
    }

    // `Result` holds either the saved task or the error, so both outcomes can be checked.
    let result: Result<BoardTask, TaskFileError>
    if let changes = spec["new"] as? [String: Any] {
        var t = BoardTask(title: "", order: 0)
        apply(changes, to: &t)
        result = Result { () throws(TaskFileError) in try folder.save(t) }
    } else {
        var t = try #require(loaded, "save and rename need an input file")
        if t.order == nil { t.order = 0 }  // the only task in its folder
        if let title = spec["rename"] as? String {
            let order = t.order
            result = Result { () throws(TaskFileError) in try folder.rename(file, to: title, order: order) }
        } else {
            apply(spec["save"] as? [String: Any] ?? [:], to: &t)
            let task = t
            result = Result { () throws(TaskFileError) in try folder.save(task) }
        }
    }

    if saveError {
        guard case .failure = result else {
            Issue.record("\(name): saving must be refused")
            return
        }
        let now = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
        #expect(now == input, "\(name): a refused file stays as it was")
        return
    }
    let saved = try result.get()
    let savedAs = spec["saved_as"] as? String ?? file
    #expect(saved.id == savedAs, "\(name): file name")
    let written = try String(contentsOf: dir.appendingPathComponent(savedAs), encoding: .utf8)
    try expectSameFile(name, actual: written, expected: try #require(after))

    // Nothing else left behind: no `.tmp` file, no old name after a rename.
    let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    #expect(left == (existing + [savedAs]).sorted(), "\(name): files in the folder after saving")
}

@Test("file names from titles")
func fileNames() throws {
    let cases = try #require(try json("file-names.json")["cases"] as? [[String: String]])
    for c in cases {
        let title = try #require(c["title"])
        #expect(TaskFormat.stem(for: title) == c["stem"], "title \(title.debugDescription)")
    }
}

@Test("a whole folder: which files count, where tasks without an order go")
func folderCase() throws {
    let expected = try #require(try json("folder.expected.json")["tasks"] as? [[String: Any]])
    // loadAll only reads, so it can run on the fixture folder itself.
    let tasks = try TaskFolder(url: fixtures.appendingPathComponent("folder")).loadAll().sorted { $0.id < $1.id }
    #expect(tasks.map(\.id) == expected.map { $0["file"] as! String })
    #expect(tasks.map(\.order) == expected.map { ($0["order"] as! NSNumber).doubleValue })
}

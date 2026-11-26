// Runs the shared cases in fixtures/capture/ (what each file looks like:
// fixtures/capture/README.md). Same idea as ConformanceTests.swift for tasks.
//
// Swift note: `@Test(arguments:)` runs a test once per value and reports each
// run on its own, so a failing fixture shows up by name.

import Foundation
import Testing

@testable import NowboardKit

/// `fixtures/capture`, found from this file's own path.
private let captureFixtures: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("fixtures/capture")
}()

private func names(in folder: String, ending suffix: String) -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: captureFixtures.appendingPathComponent(folder).path)) ?? []
    return files.filter { $0.hasSuffix(suffix) }.map { String($0.dropLast(suffix.count)) }.sorted()
}

private func jsonObject(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: captureFixtures.appendingPathComponent(path))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func text(_ path: String) throws -> String {
    try String(contentsOf: captureFixtures.appendingPathComponent(path), encoding: .utf8)
}

// MARK: - Classifier results

private let classifierCases = names(in: "classifier", ending: ".json")
private let dailyNoteCases = names(in: "daily-note", ending: ".case.json")

@Test func fixturesAreFound() {
    // If the folder moved, the `arguments:` lists below would be empty and
    // every test would pass without running. This catches that.
    #expect(classifierCases.count >= 20)
    #expect(dailyNoteCases.count >= 15)
    #expect(pathCases.count >= 50)
    #expect(rawCases.count >= 5)
    #expect(rawTimeZone == "UTC")
}

@Test(arguments: classifierCases)
func classifierResult(name: String) throws {
    let c = try jsonObject("classifier/\(name).json")
    let categories = c["categories"] as! [String]
    let input: Data
    if let raw = c["input_text"] as? String {
        input = Data(raw.utf8)
    } else {
        input = try JSONSerialization.data(withJSONObject: c["input"]!, options: [.fragmentsAllowed])
    }
    let expected = c["expected"] as! [String: Any]

    let result: CaptureResult
    do {
        result = try CaptureResult.decode(input, categoryIds: categories)
    } catch {
        #expect(expected["error"] as? Bool == true, "\(name): unexpected error \(error)")
        return
    }
    #expect(expected["error"] == nil, "\(name): should have been refused")
    #expect(result.kind.rawValue == expected["kind"] as? String, "\(name): kind")
    #expect(result.title == expected["title"] as? String, "\(name): title")
    #expect(result.body == expected["body"] as? String, "\(name): body")
    #expect(result.area == expected["area"] as? String, "\(name): area")
    #expect(result.status?.rawValue == expected["status"] as? String, "\(name): status")
    #expect(result.folder == expected["folder"] as? String, "\(name): folder")
    #expect(result.confidence == (expected["confidence"] as? NSNumber)?.doubleValue, "\(name): confidence")
    #expect(result.followUp == expected["follow_up"] as? String, "\(name): follow_up")
    #expect(result.needsQuestion == expected["needs_question"] as? Bool, "\(name): needs_question")
    #expect((result.needsQuestion ? result.question : nil) == expected["question"] as? String, "\(name): question")
}

// MARK: - Daily notes

@Test(arguments: dailyNoteCases)
func dailyNote(name: String) throws {
    let c = try jsonObject("daily-note/\(name).case.json")
    let input = try text("daily-note/\(name).input.md")
    let after = try text("daily-note/\(name).after.md")
    let got = DailyNote.appendingCaptured(c["line"] as! String, to: input)
    #expect(got == after, "\(name): \(c["description"] as! String)")
}

// MARK: - Vault paths

private struct PathCase: Sendable, CustomTestStringConvertible {
    var path: String
    var valid: Bool
    var description: String
    var isFolder: Bool
    var normalized: String?
    var testDescription: String { "\(isFolder ? "folder" : "file") “\(path.debugDescription)” – \(description)" }
}

private let pathCases: [PathCase] = {
    guard let object = try? jsonObject("vault-paths.json") else { return [] }
    func cases(_ key: String, folder: Bool) -> [PathCase] {
        (object[key] as? [[String: Any]] ?? []).map {
            PathCase(
                path: $0["path"] as! String, valid: $0["valid"] as! Bool, description: $0["description"] as! String,
                isFolder: folder, normalized: $0["normalized"] as? String)
        }
    }
    return cases("file_paths", folder: false) + cases("folder_paths", folder: true)
}()

@Test(arguments: pathCases)
private func vaultPath(c: PathCase) throws {
    func check() throws(VaultPathError) -> String { c.isFolder ? try VaultPath.folder(c.path) : try VaultPath.file(c.path) }
    if c.valid {
        #expect((try? check()) == (c.normalized ?? c.path))
    } else {
        #expect((try? check()) == nil, "should be refused")
    }
}

// MARK: - Raw captures

private struct RawCase: Sendable, CustomTestStringConvertible {
    var description: String
    var text: String
    var time: String
    var existing: [String]
    var file: String
    var content: String
    var testDescription: String { description }
}

// Swift note: a global `let` holding `[String: Any]` isn't allowed (`Any` isn't
// `Sendable`), so the JSON is read inside the initialiser and only Sendable
// values (`RawCase`, `[String]`) are kept.
private let rawTimeZone: String = (try? jsonObject("raw-captures.json"))?["time_zone"] as? String ?? ""
private let refusedTexts: [String] = (try? jsonObject("raw-captures.json"))?["refused_texts"] as? [String] ?? []
private let rawCases: [RawCase] = ((try? jsonObject("raw-captures.json"))?["cases"] as? [[String: Any]] ?? []).map {
    RawCase(
        description: $0["description"] as! String, text: $0["text"] as! String, time: $0["time"] as! String,
        existing: $0["existing"] as! [String], file: $0["file"] as! String, content: $0["content"] as! String)
}

/// `2026-11-26T13:05:22` in UTC, as a Date.
private func date(_ text: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: text + "Z")!
}

@Test(arguments: rawCases)
private func rawCapture(c: RawCase) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-capture-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in c.existing {
        try "OLD".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let inbox = CaptureInbox(folder: dir)
    let utc = try #require(TimeZone(identifier: rawTimeZone))

    let name = try inbox.writeRaw(c.text, at: date(c.time), timeZone: utc)
    #expect(name == c.file)
    #expect(try text(at: dir, name) == c.content)
    // Nothing else changed: the old files are untouched, and no temp file is left.
    for old in c.existing { #expect(try text(at: dir, old) == "OLD") }
    let all = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    #expect(all == (c.existing + [c.file]).sorted())
}

@Test func refusedCaptureTexts() throws {
    let refused = refusedTexts
    #expect(refused.count >= 3)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-capture-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let inbox = CaptureInbox(folder: dir)
    for t in refused {
        #expect(throws: CaptureError.emptyText) { try inbox.writeRaw(t) }
    }
    // Nothing was written; the folder wasn't even created.
    #expect(!FileManager.default.fileExists(atPath: dir.path))
}

private func text(at dir: URL, _ name: String) throws -> String {
    try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
}

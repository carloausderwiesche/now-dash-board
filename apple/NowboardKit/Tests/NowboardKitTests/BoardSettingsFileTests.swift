// `.nowboard.json` (spec 7): the shared categories.

import Foundation
import Testing

@testable import NowboardKit

private func folder(_ settings: String? = nil) throws -> TaskFolder {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-settings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let settings {
        try settings.write(to: dir.appendingPathComponent(".nowboard.json"), atomically: true, encoding: .utf8)
    }
    return TaskFolder(url: dir)
}

@Test func noFileOrNoListMeansNoCategories() throws {
    #expect(try folder().loadCategories() == nil)
    #expect(try folder("{\"categories\": []}").loadCategories() == nil)
    #expect(try folder("{\"other\": 1}").loadCategories() == nil)
}

@Test func categoriesAreReadInOrder() throws {
    let f = try folder(#"{"categories": [{"id": "work", "name": "Work", "color": "blue"}, {"id": "home", "name": "Home", "color": "rose"}]}"#)
    #expect(try f.loadCategories()?.map(\.id) == ["work", "home"])
}

@Test func savingKeepsKeysWeDontKnow() throws {
    let f = try folder(#"{"categories": [], "fromTheFuture": {"a": 1}}"#)
    try f.saveCategories([CategoryRecord(id: "work", name: "Work", color: "blue")])
    let text = try String(contentsOf: f.url.appendingPathComponent(".nowboard.json"), encoding: .utf8)
    #expect(text.contains("fromTheFuture"))
    #expect(try f.loadCategories() == [CategoryRecord(id: "work", name: "Work", color: "blue")])
}

@Test func aBrokenFileIsNeverOverwritten() throws {
    let f = try folder("{ not json")
    #expect(throws: TaskFileError.invalidSettings) { try f.loadCategories() }
    #expect(throws: TaskFileError.invalidSettings) { try f.saveCategories([]) }
    #expect(try String(contentsOf: f.url.appendingPathComponent(".nowboard.json"), encoding: .utf8) == "{ not json")
}

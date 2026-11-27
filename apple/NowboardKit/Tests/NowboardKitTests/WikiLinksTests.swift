// Rewriting links when a note moves, against the shared cases in fixtures/vault-changes/.

import Foundation
import Testing

@testable import NowboardKit

private let linkCases: [LinkCase] = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    guard let data = try? Data(contentsOf: url.appendingPathComponent("fixtures/vault-changes/link-rewrite.json")),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = object["cases"] as? [[String: Any]]
    else { return [] }
    return list.map {
        LinkCase(
            description: $0["description"] as! String, old: $0["old"] as! String, new: $0["new"] as! String, notes: $0["notes"] as! [String],
            input: $0["input"] as! String, expected: $0["expected"] as! String, changed: $0["changed"] as! Int,
            ambiguous: $0["ambiguous"] as! Int)
    }
}()

private struct LinkCase: Sendable, CustomTestStringConvertible {
    var description: String
    var old: String
    var new: String
    var notes: [String]
    var input: String
    var expected: String
    var changed: Int
    var ambiguous: Int
    var testDescription: String { description }
}

@Test func theLinkCasesAreFound() {
    #expect(linkCases.count >= 30)
}

@Test(arguments: linkCases)
private func rewritingLinks(c: LinkCase) {
    let result = WikiLinks.rewrite(c.input, moving: c.old, to: c.new, notes: c.notes)
    #expect(result.text == c.expected)
    #expect(result.changed == c.changed)
    #expect(result.ambiguous == c.ambiguous)
}

@Test func rewritingTwiceChangesNothingMore() {
    let notes = ["Wiki/Plan.md", "Wiki/Other.md"]
    let once = WikiLinks.rewrite("[[Plan]] [[Wiki/Plan#x|y]] ![[Plan]]", moving: "Wiki/Plan.md", to: "Wiki/Roadmap.md", notes: notes)
    // After the move, the vault has the new path; the old links are gone, so nothing matches any more.
    let after = ["Wiki/Roadmap.md", "Wiki/Other.md"]
    let twice = WikiLinks.rewrite(once.text, moving: "Wiki/Plan.md", to: "Wiki/Roadmap.md", notes: after)
    #expect(twice.text == once.text)
    #expect(twice.changed == 0)
}

@Test func aMoveThenItsReverseGivesTheOriginalText() {
    let text = "a [[Wiki/Plan|x]] b ![[Wiki/Plan#h]]"
    let there = WikiLinks.rewrite(text, moving: "Wiki/Plan.md", to: "Archive/Plan.md", notes: ["Wiki/Plan.md"])
    let back = WikiLinks.rewrite(there.text, moving: "Archive/Plan.md", to: "Wiki/Plan.md", notes: ["Archive/Plan.md"])
    #expect(back.text == text)
}

@Test func textWithoutLinksIsReturnedUnchangedByte_forByte() {
    let text = "plain\r\n\twith   odd\u{00A0}spaces\n\n[not] a [link]\n"
    let result = WikiLinks.rewrite(text, moving: "A.md", to: "B.md", notes: ["A.md"])
    #expect(result.text == text && result.changed == 0)
}

@Test func aVeryLongLineIsFine() {
    let text = String(repeating: "[[Plan]] ", count: 5000)
    let result = WikiLinks.rewrite(text, moving: "Wiki/Plan.md", to: "Wiki/Roadmap.md", notes: ["Wiki/Plan.md"])
    #expect(result.changed == 5000)
}

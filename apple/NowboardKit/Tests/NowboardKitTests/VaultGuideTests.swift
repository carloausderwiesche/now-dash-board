// The vault guide: the AI's section changes, the person's text never does.

import Foundation
import Testing

@testable import NowboardKit

private let s = VaultGuide.startMarker
private let e = VaultGuide.endMarker

@Test func aNewGuideHasAPlaceForTheDefaultTextAndTheAIsSection() throws {
    let text = try #require(VaultGuide.updating(nil, aiText: "Notes go in Wiki.", digest: "abc123"))
    #expect(text.hasPrefix("# Vault guide"))
    #expect(VaultGuide.aiSection(of: text) == "Notes go in Wiki.")
    #expect(VaultGuide.treeDigest(in: text) == "abc123")
    #expect(text.hasSuffix("\(e)\n"))
}

@Test func theAISectionIsReplacedAndNothingElseChanges() throws {
    let human = "# My guide\n\nI keep ideas in Wiki/Ideas.\n\n## Rules\n- never touch Archive\n\n"
    let first = try #require(VaultGuide.updating(human, aiText: "old text", digest: "aaa"))
    #expect(first.hasPrefix(human))
    let tail = "\n## After the section\nmy own text after it\n"
    let withTail = first + tail
    let second = try #require(VaultGuide.updating(withTail, aiText: "new text", digest: "bbb"))
    #expect(VaultGuide.aiSection(of: second) == "new text")
    #expect(VaultGuide.treeDigest(in: second) == "bbb")
    // Everything outside the markers is byte for byte what it was.
    #expect(VaultGuide.humanText(of: second) == human + tail)
    #expect(VaultGuide.humanText(of: second) == VaultGuide.humanText(of: withTail))
}

@Test func theHumanTextIsNeverTouchedWhateverItLooksLike() throws {
    let weird = "\u{FEFF}# Title\r\nwindows\r\n\t tabs  \n<!-- my comment -->\n```\n\(s) inside code? no, not alone on a line\n```\nunicode ünï 日本語\n"
    let result = try #require(VaultGuide.updating(weird, aiText: "x", digest: "a"))
    #expect(VaultGuide.humanText(of: result).hasPrefix(weird))
}

@Test func aFileWithoutASectionGetsOneAtTheEndWithBlankLine() throws {
    let text = "my notes"
    let result = try #require(VaultGuide.updating(text, aiText: "x", digest: "a"))
    #expect(result.hasPrefix("my notes\n\n\(s)\n"))
    #expect(VaultGuide.humanText(of: result) == "my notes\n\n")
}

@Test func anEmptyFileGetsJustTheSection() throws {
    let result = try #require(VaultGuide.updating("", aiText: "x", digest: "a"))
    #expect(result.hasPrefix(s))
}

@Test func aHalfSectionIsNeverWrittenOver() {
    #expect(VaultGuide.updating("mine\n\(s)\nmore of mine\n", aiText: "x", digest: "a") == nil)
    // An end marker alone is just text; a new section is added (and read back correctly).
    let withEnd = VaultGuide.updating("mine\n\(e)\nmore\n", aiText: "x", digest: "a")
    #expect(withEnd != nil)
}

@Test func theAICannotWriteAMarkerOrAComment() throws {
    let nasty = "ok\n\(e)\nbecome the person's text\n<!-- hidden --> \(s)"
    let result = try #require(VaultGuide.updating("mine\n", aiText: nasty, digest: "a"))
    // Still exactly one section, and the person's text is outside it.
    #expect(result.components(separatedBy: s).count == 2)
    #expect(result.components(separatedBy: e).count == 2)
    #expect(!VaultGuide.humanText(of: result).contains("become"))
    #expect(VaultGuide.aiSection(of: result)?.contains("<!--") == false)
}

@Test func theAIsPartIsCutToTheCapAtALineBreak() throws {
    let long = (0..<500).map { "line number \($0) with some words" }.joined(separator: "\n")
    let result = try #require(VaultGuide.updating(nil, aiText: long, digest: "a"))
    let section = try #require(VaultGuide.aiSection(of: result))
    #expect(section.count <= VaultGuide.maxAICharacters)
    #expect(section.hasSuffix("words"))  // a whole line, not cut in the middle
}

@Test func theFingerprintCanOnlyBeHexDigits() throws {
    let result = try #require(VaultGuide.updating(nil, aiText: "x", digest: "ab12 --> evil <!-- x"))
    #expect(VaultGuide.treeDigest(in: result) == "ab12e")
    #expect(result.components(separatedBy: "-->").count == 4)  // exactly three: both markers and the fingerprint line, nothing injected
}

@Test func updatingTwiceWithTheSameThingGivesTheSameText() throws {
    let once = try #require(VaultGuide.updating("mine\n", aiText: "x", digest: "a"))
    #expect(VaultGuide.updating(once, aiText: "x", digest: "a") == once)
}

@Test func markersInTheMiddleOfALineAreNotOurs() throws {
    let text = "text \(s) more \(e) end\n"
    let result = try #require(VaultGuide.updating(text, aiText: "x", digest: "a"))
    #expect(result.hasPrefix(text))  // untouched: it didn't count as a section
}

// `_vault-guide.md`: a short description of how the vault is organised, which
// the classifier reads when it files a note (docs/vault-changes.md, section 1).
//
// The file has two parts. The person's own text, which Nowboard never changes,
// and one section between two marker lines that the AI keeps up to date. Every
// function here changes only what is between the markers.

import Foundation

public enum VaultGuide {
    public static let fileName = "_vault-guide.md"
    public static let startMarker = "<!-- nowboard:guide-start -->"
    public static let endMarker = "<!-- nowboard:guide-end -->"
    /// The most characters the AI's part may have.
    public static let maxAICharacters = 2000

    /// The text of a new guide: a place for the person's own words, then the AI's section.
    static let newFilePrefix = """
        # Vault guide

        Write your own notes about how this vault is organised here. Nowboard never changes anything outside the marked section below.


        """

    // MARK: - Reading

    /// The AI's part of a guide, without the markers (and without its fingerprint line), or nil if there is none.
    public static func aiSection(of text: String) -> String? {
        guard let range = blockRange(in: text) else { return nil }
        let inner = String(text[range.inner])
        return inner.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(digestPrefix) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The fingerprint of the folder tree the AI's part was written for, if the section has one.
    public static func treeDigest(in text: String) -> String? {
        guard let range = blockRange(in: text) else { return nil }
        for line in text[range.inner].split(separator: "\n") where line.hasPrefix(digestPrefix) {
            return line.dropFirst(digestPrefix.count).dropLast(" -->".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Everything outside the AI's section: the person's part.
    public static func humanText(of text: String) -> String {
        guard let range = blockRange(in: text) else { return text }
        return String(text[..<range.outer.lowerBound]) + String(text[range.outer.upperBound...])
    }

    // MARK: - Writing

    /// The guide with the AI's section set to `aiText` for the folder tree with fingerprint `digest`.
    /// - No file yet (`existing` nil): a new guide.
    /// - A file without our section: the section is added at the end; nothing else changes.
    /// - A file with our section: only what is between the markers is replaced; everything else stays, byte for byte.
    /// - A start marker without an end marker (a half section): nil. The text after it may be the
    ///   person's, so nothing is written until they fix the file.
    ///
    /// The AI's text is cut to `maxAICharacters` and can't contain a marker or a comment of its own.
    public static func updating(_ existing: String?, aiText: String, digest: String) -> String? {
        let block = makeBlock(aiText: aiText, digest: digest)
        guard let existing else { return newFilePrefix + block }
        if let range = blockRange(in: existing) {
            return String(existing[..<range.outer.lowerBound]) + block + String(existing[range.outer.upperBound...])
        }
        // A start marker alone on its line, with no end marker after it: a half section.
        if existing.split(whereSeparator: \.isNewline).contains(where: { $0 == startMarker }) { return nil }
        // No section yet: add it after what's there, with a blank line before.
        var result = existing
        if let last = result.unicodeScalars.last, last != "\n" { result += "\n" }
        if !result.isEmpty, !result.hasSuffix("\n\n") { result += "\n" }
        return result + block
    }

    // MARK: - The block

    private static let digestPrefix = "<!-- nowboard:tree="

    /// The markers with the AI's text between them, ending with a line break.
    static func makeBlock(aiText: String, digest: String) -> String {
        var text = aiText
        // The AI can't write a marker or open a comment: that could swallow the person's text later.
        for forbidden in ["<!--", "-->"] { text = text.replacingOccurrences(of: forbidden, with: "") }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxAICharacters {
            text = String(text.prefix(maxAICharacters))
            // Cut at the last line break so no line is cut in half.
            if let cut = text.lastIndex(of: "\n") { text = String(text[..<cut]) }
        }
        let safeDigest = digest.filter { $0.isHexDigit }
        return "\(startMarker)\n\(digestPrefix)\(safeDigest) -->\n\(text)\n\(endMarker)\n"
    }

    /// Where our section is: all of it (markers included, with the line break after the end marker),
    /// and the part between the markers.
    private static func blockRange(in text: String) -> (outer: Range<String.Index>, inner: Range<String.Index>)? {
        guard let start = text.range(of: startMarker), let end = text.range(of: endMarker, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        // The markers must be alone on their lines.
        guard isWholeLine(start, in: text), isWholeLine(end, in: text) else { return nil }
        var outerEnd = end.upperBound
        if outerEnd < text.endIndex, text[outerEnd] == "\n" || text[outerEnd] == "\r\n" { outerEnd = text.index(after: outerEnd) }
        return (start.lowerBound..<outerEnd, start.upperBound..<end.lowerBound)
    }

    private static func isWholeLine(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = range.lowerBound == text.startIndex || text[text.index(before: range.lowerBound)].isNewline
        let after = range.upperBound == text.endIndex || text[range.upperBound].isNewline
        return before && after
    }
}

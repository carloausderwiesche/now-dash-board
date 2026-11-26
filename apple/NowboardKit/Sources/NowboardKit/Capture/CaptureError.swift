// What can go wrong with a capture (docs/capture-format.md), and one small
// text helper the capture code shares.

import Foundation

/// What can go wrong when reading a classifier answer or writing a capture.
///
/// Swift note: an `enum` with cases that carry a value (`io(String)`) is how
/// Swift models "one of these things went wrong". `LocalizedError` gives each
/// case a sentence that can be shown to the user as it is.
public enum CaptureError: Error, Equatable, LocalizedError {
    /// The typed text was empty or only whitespace, so nothing is written (spec 2).
    case emptyText
    /// The classifier's answer can't be used. The message says why (spec 4.2).
    case invalidResult(String)
    /// The disk refused (full, no permission…).
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText: "There is nothing to capture."
        case .invalidResult(let why): "The classifier's answer can't be used: \(why)"
        case .io(let message): message
        }
    }
}

extension String {
    /// The text as one trimmed line (spec 4.2): split at line breaks, trim
    /// every piece, drop empty ones, join with one space.
    ///
    /// Swift note: `.newlines` covers `\n`, `\r\n` and a few more; `\r\n` is
    /// one break, not two.
    var asOneLine: String {
        components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

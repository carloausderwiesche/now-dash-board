// The Inbox folder and the raw capture files in it (spec 1 and 2).
//
// The golden rule: the typed text is saved FIRST, before any classifying, so
// nothing a person typed is ever lost.

import Foundation

/// `<vault>/Notes/Inbox`.
public struct CaptureInbox: Sendable {
    /// Where the Inbox is, relative to the vault.
    public static let relativeFolder = "Notes/Inbox"

    public let url: URL

    /// The Inbox of a vault.
    public init(vault: URL) {
        self.url = vault.appendingPathComponent(Self.relativeFolder, isDirectory: true)
    }

    /// The Inbox at an exact folder (for tests).
    public init(folder: URL) {
        self.url = folder
    }

    /// Saves one capture as a new file and returns its name (spec 2).
    ///
    /// `time` is when it was typed and `timeZone` says whose "local" it is:
    /// the phone's, normally. The file is never overwritten: if the name is
    /// taken, the next one is used (`… (2).md`).
    @discardableResult
    public func writeRaw(_ text: String, at time: Date = Date(), timeZone: TimeZone = .current) throws(CaptureError) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyText }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .io(error.localizedDescription)
        }
        let content = "---\ncaptured: \(TaskFormat.timestamp(time, timeZone: timeZone))\n---\n" + text
        let stem = Self.fileStem(time, timeZone: timeZone)

        // Write the whole content to a hidden temporary file first: readers
        // skip names starting with a dot, so nobody sees a half-written capture.
        let tmp = url.appendingPathComponent(".capture-\(UUID().uuidString).tmp")
        do {
            try Data(content.utf8).write(to: tmp)
        } catch {
            throw .io(error.localizedDescription)
        }
        // Whatever happens next, the temporary file goes away.
        defer { unlink(tmp.path) }

        var n = 1
        while true {
            let name = n == 1 ? "\(stem).md" : "\(stem) (\(n)).md"
            // `link` gives the temporary file a second name, and FAILS if that
            // name exists. That's what makes this create-only: unlike a
            // "check, then write", nobody can slip in between. (A plain
            // `rename` would silently replace an existing file.)
            if Darwin.link(tmp.path, url.appendingPathComponent(name).path) == 0 {
                return name
            }
            guard errno == EEXIST else { throw .io(String(cString: strerror(errno))) }
            n += 1
        }
    }

    /// `2026-11-26 13-05-22` (no colons: some systems can't have them in file names).
    static func fileStem(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f.string(from: date)
    }
}

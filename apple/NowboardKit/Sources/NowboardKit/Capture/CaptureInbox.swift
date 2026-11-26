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
        // Registered BEFORE writing, so a half-written temporary file goes away too.
        defer { unlink(tmp.path) }
        do {
            try Data(content.utf8).write(to: tmp)
        } catch {
            throw .io(error.localizedDescription)
        }

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
            let code = errno
            if code == EEXIST {
                n += 1
                continue
            }
            // Some volumes (exFAT, certain network and cloud folders) have no
            // hard links. Typed text must never be lost, so there we create
            // the final file directly, still never replacing anything
            // (`O_EXCL`). It isn't atomic, but it is complete or removed.
            if code == ENOTSUP || code == EPERM || code == ENOSYS {
                switch Self.createExclusively(Data(content.utf8), at: url.appendingPathComponent(name)) {
                case 0: return name
                case EEXIST: n += 1
                case let failure: throw .io(String(cString: strerror(failure)))
                }
                continue
            }
            throw .io(String(cString: strerror(code)))
        }
    }

    /// Creates a file that must not exist yet and writes `data` into it.
    /// Returns 0 or an error number (`EEXIST` if the name is taken). A file
    /// that was created but couldn't be written completely is removed again.
    ///
    /// Swift note: `open`, `write` and `close` are the plain C system calls;
    /// they report failure with -1 and leave the reason in `errno`.
    static func createExclusively(_ data: Data, at file: URL) -> Int32 {
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard fd >= 0 else { return errno }
        var written = 0
        var failure: Int32 = 0
        data.withUnsafeBytes { buffer in
            while written < buffer.count {
                let n = write(fd, buffer.baseAddress! + written, buffer.count - written)
                if n < 0 { failure = errno; return }
                written += n
            }
        }
        if close(fd) != 0 && failure == 0 { failure = errno }
        if failure != 0 { unlink(file.path) }
        return failure
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

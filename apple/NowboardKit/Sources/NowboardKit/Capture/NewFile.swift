// Creating a new file that must not exist yet: the one way the app makes
// files in the vault (raw captures, filed notes). Never overwrites.

import Foundation

enum NewFile {
    /// Saves `content` as `<stem>.md` in `folder` (made if missing) and returns
    /// the file name. If the name is taken, `<stem> (2).md`, `(3)` and so on.
    ///
    /// The file appears complete or not at all, and an existing file is never
    /// replaced, even if someone creates the same name at the same moment.
    static func create(_ content: String, in folder: URL, stem: String) throws(CaptureError) -> String {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .io(error.localizedDescription)
        }

        // Write the whole content to a hidden temporary file first: readers
        // skip names starting with a dot, so nobody sees a half-written capture.
        let tmp = folder.appendingPathComponent(".capture-\(UUID().uuidString).tmp")
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
            if Darwin.link(tmp.path, folder.appendingPathComponent(name).path) == 0 {
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
                switch CaptureInbox.createExclusively(Data(content.utf8), at: folder.appendingPathComponent(name)) {
                case 0: return name
                case EEXIST: n += 1
                case let failure: throw .io(String(cString: strerror(failure)))
                }
                continue
            }
            throw .io(String(cString: strerror(code)))
        }
    }
}

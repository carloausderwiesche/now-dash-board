// Where things are in the vault: the folders the capture pipeline reads and
// writes. Everything is a path relative to the vault root, so a vault in
// iCloud, on the Mac or in a test's temporary folder all work the same.

import Foundation

public struct VaultConfig: Sendable, Equatable {
    /// The vault's root folder (the one with `.obsidian` in it).
    public var vault: URL
    /// Where tasks live, relative to the vault. Notes can never be filed here.
    public var tasksPath: String
    /// Where raw captures live (spec 2).
    public var inboxPath: String
    /// Where daily notes live, relative to the vault; empty = the vault root.
    public var dailyNotesFolder: String
    /// The daily notes' file name, in Obsidian's date format (`YYYY-MM-DD`).
    public var dailyNoteFormat: String

    public static let defaultTasksPath = "Notes/Tasks"
    public static let defaultDailyFormat = "YYYY-MM-DD"

    public init(
        vault: URL, tasksPath: String = defaultTasksPath, inboxPath: String = CaptureInbox.relativeFolder,
        dailyNotesFolder: String = "", dailyNoteFormat: String = defaultDailyFormat
    ) {
        self.vault = vault
        self.tasksPath = tasksPath
        self.inboxPath = inboxPath
        self.dailyNotesFolder = dailyNotesFolder
        self.dailyNoteFormat = dailyNoteFormat
    }

    public var tasksURL: URL { vault.appendingPathComponent(tasksPath, isDirectory: true) }
    public var inbox: CaptureInbox { CaptureInbox(folder: vault.appendingPathComponent(inboxPath, isDirectory: true)) }
    /// Folders a model-chosen path may not use (`VaultPath`).
    public var reservedFolders: [String] { [tasksPath] }

    // MARK: - Reading the vault's own settings

    /// The config for a vault. `tasksFolder` is the Tasks folder the board
    /// uses, if it isn't the default place. The daily notes' folder and file
    /// name format come from Obsidian's `.obsidian/daily-notes.json` when it
    /// has them; otherwise the defaults (the vault root, `YYYY-MM-DD`).
    public static func load(vault: URL, tasksFolder: URL? = nil) -> VaultConfig {
        var config = VaultConfig(vault: vault)
        if let tasksFolder, let relative = relativePath(of: tasksFolder, in: vault) {
            config.tasksPath = relative
        }
        let settings = vault.appendingPathComponent(".obsidian/daily-notes.json")
        if let data = try? Data(contentsOf: settings),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            // The values come from a file anyone can edit, so they're checked
            // like a model's path: a bad one is ignored.
            if let folder = (object["folder"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
                !folder.isEmpty, (try? VaultPath.folder(folder, reserved: [])) != nil
            {
                config.dailyNotesFolder = folder
            }
            if let format = (object["format"] as? String)?.trimmedOrNil, formatDay(format, date: Date(), timeZone: .current) != nil {
                config.dailyNoteFormat = format
            }
        }
        return config
    }

    /// The vault a folder is in: the nearest folder above it with an
    /// `.obsidian` folder. (The app uses this too.)
    public static func vaultRoot(of folder: URL) -> URL? {
        var root = folder.standardizedFileURL
        while root.pathComponents.count > 1 {
            root.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(".obsidian").path) { return root }
        }
        return nil
    }

    private static func relativePath(of folder: URL, in vault: URL) -> String? {
        let root = vault.resolvingSymlinksInPath().standardizedFileURL.path
        let path = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }

    // MARK: - Daily notes

    /// The daily note's path for a day, e.g. `Daily/2026-11-26.md`.
    /// A format we can't read falls back to the default one.
    public func dailyNotePath(for date: Date, timeZone: TimeZone = .current) -> String {
        let name = Self.formatDay(dailyNoteFormat, date: date, timeZone: timeZone)
            ?? Self.formatDay(Self.defaultDailyFormat, date: date, timeZone: timeZone)!
        let folder = dailyNotesFolder.isEmpty ? "" : dailyNotesFolder + "/"
        return folder + name + ".md"
    }

    /// A day in Obsidian's format. Understands `YYYY`, `YY`, `MM`, `M`, `DD`,
    /// `D`, text in `[brackets]` and punctuation (`-`, `.`, `_`, space, `/`);
    /// any other letter (`dddd`, `Q`…) means we don't know the format: nil.
    static func formatDay(_ format: String, date: Date, timeZone: TimeZone) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return nil }
        func pad(_ n: Int, _ width: Int) -> String { String(format: "%0\(width)d", n) }

        let chars = Array(format)
        var out = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            // How many of the same letter in a row.
            var run = 1
            while i + run < chars.count, chars[i + run] == ch { run += 1 }
            switch (ch, run) {
            case ("[", _):
                guard let end = chars[i...].firstIndex(of: "]") else { return nil }
                out += String(chars[(i + 1)..<end])
                i = end + 1
                continue
            case ("Y", 4): out += pad(year, 4)
            case ("Y", 2): out += pad(year % 100, 2)
            case ("M", 2): out += pad(month, 2)
            case ("M", 1): out += String(month)
            case ("D", 2): out += pad(day, 2)
            case ("D", 1): out += String(day)
            default:
                guard !ch.isLetter else { return nil }
                out += String(repeating: ch, count: run)
            }
            i += run
        }
        return out.isEmpty ? nil : out
    }
}

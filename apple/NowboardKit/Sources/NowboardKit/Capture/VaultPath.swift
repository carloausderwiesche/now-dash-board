// Paths chosen by the model (spec 5). The classifier suggests where a note
// goes, but a model can be tricked by the very text it reads ("file this
// under ../../Library"), so its path is untrusted text. Nothing is created
// from it until it has passed every check here. A path that fails is refused,
// never "repaired".

import Foundation

/// Why a path was refused.
public enum VaultPathError: Error, Equatable, LocalizedError {
    case empty
    case absolute
    case badPart(String, why: String)
    case tooDeep
    case tooLong
    case notMarkdown
    /// The folder is a symbolic link (or sits behind one) that leads out of the vault.
    case escapesVault

    public var errorDescription: String? {
        switch self {
        case .empty: "The path is empty."
        case .absolute: "The path must be relative to the vault."
        case .badPart(let part, let why): "“\(part)” is not allowed in a path: \(why)."
        case .tooDeep: "The path is nested too deep."
        case .tooLong: "The path is too long."
        case .notMarkdown: "The file must be a .md file."
        case .escapesVault: "The path leads outside the vault."
        }
    }
}

public enum VaultPath {
    /// Most folders in a path (the file name doesn't count).
    public static let maxDepth = 4
    /// Most Unicode scalars in one part. Counted like task titles (task format 4.1).
    public static let maxPartLength = 80
    public static let maxPathLength = 240

    /// The characters a part can't hold: the ones task titles lose (task format 4.1).
    private static let forbidden = Set("/\\:*?\"<>|#^[]".unicodeScalars)

    /// A file path like `Wiki/Projects/Idea.md`. Returns it as it is when it's fine.
    public static func file(_ path: String) throws(VaultPathError) -> String {
        let parts = try split(path)
        // At least a name; the last part is the file, the others are folders.
        guard parts.count - 1 <= maxDepth else { throw .tooDeep }
        let name = parts[parts.count - 1]
        // Swift note: `hasSuffix` compares exactly here, so `.MD` fails.
        guard name.hasSuffix(".md") else { throw .notMarkdown }
        let stem = name.dropLast(3)
        guard !stem.isEmpty else { throw .notMarkdown }
        if let last = stem.unicodeScalars.last, last == "." || CharacterSet.whitespaces.contains(last) {
            throw .badPart(name, why: "the name can't end with a space or a dot")
        }
        return path
    }

    /// A folder path like `Wiki/Projects`. A folder can't be named `x.md`: that's a file.
    public static func folder(_ path: String) throws(VaultPathError) -> String {
        let parts = try split(path)
        guard parts.count <= maxDepth else { throw .tooDeep }
        if let last = parts.last, last.hasSuffix(".md") {
            throw .badPart(last, why: "that's a file name, not a folder")
        }
        return path
    }

    /// The checks both kinds share: returns the parts of the path.
    private static func split(_ path: String) throws(VaultPathError) -> [String] {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .empty }
        guard path.unicodeScalars.count <= maxPathLength else { throw .tooLong }
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\") else { throw .absolute }
        // `omittingEmptySubsequences: false` keeps the empty part in `a//b`
        // and in a trailing slash, so we can refuse them.
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for part in parts {
            if part.isEmpty { throw .badPart(part, why: "empty part") }
            if part == "." || part == ".." { throw .badPart(part, why: "no . or .. allowed") }
            if part.hasPrefix(".") { throw .badPart(part, why: "hidden names are not allowed") }
            if part.unicodeScalars.count > maxPartLength { throw .tooLong }
            for scalar in part.unicodeScalars {
                // Control characters (line breaks, NUL) and "format" ones
                // (right-to-left overrides, zero-width spaces), which can make
                // a name look like something else.
                let category = scalar.properties.generalCategory
                if forbidden.contains(scalar) || category == .control || category == .format {
                    throw .badPart(part, why: "it has a character that can break file names")
                }
            }
            if let first = part.unicodeScalars.first, CharacterSet.whitespaces.contains(first) {
                throw .badPart(part, why: "it starts with a space")
            }
            if let last = part.unicodeScalars.last, CharacterSet.whitespaces.contains(last) || last == "." {
                throw .badPart(part, why: "it ends with a space or a dot")
            }
        }
        return parts
    }

    // MARK: - From a path to a real location

    /// The location of a checked **file** path inside `vault`.
    ///
    /// A second line of defence: the text checks above can't see a symbolic
    /// link (an alias) in the vault that points somewhere else. So we also
    /// follow the links of the deepest folder that already exists and make
    /// sure the file would still be inside the vault.
    public static func resolve(file path: String, in vault: URL) throws(VaultPathError) -> URL {
        _ = try file(path)
        return try locate(path, in: vault)
    }

    /// Same for a **folder** path.
    public static func resolve(folder path: String, in vault: URL) throws(VaultPathError) -> URL {
        _ = try folder(path)
        return try locate(path, in: vault)
    }

    private static func locate(_ path: String, in vault: URL) throws(VaultPathError) -> URL {
        let root = vault.resolvingSymlinksInPath().standardizedFileURL
        let target = root.appendingPathComponent(path)
        let real = realLocation(of: target, linksLeft: 20)
        // Compare with a trailing slash so `/vault2` doesn't count as inside `/vault`.
        guard let real, (real.path + "/").hasPrefix(root.path + "/") else { throw .escapesVault }
        return target
    }

    /// Where `url` really is once every symbolic link on the way is followed,
    /// including links that point at something that doesn't exist (yet):
    /// writing to such a link would create the file at its target. Nil if
    /// there are too many links in a row (a loop).
    ///
    /// `attributesOfItem` looks at the link itself and doesn't follow it,
    /// unlike `fileExists`, which would call a dangling link "not there".
    private static func realLocation(of url: URL, linksLeft: Int) -> URL? {
        let fm = FileManager.default
        // Walk up to the nearest part that exists (a link counts as existing).
        var existing = url
        var rest: [String] = []
        while (try? fm.attributesOfItem(atPath: existing.path)) == nil, existing.path != "/" {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var base: URL
        if let destination = try? fm.destinationOfSymbolicLink(atPath: existing.path) {
            guard linksLeft > 0 else { return nil }
            // A relative link starts from the folder that holds the link.
            let next = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : existing.deletingLastPathComponent().appendingPathComponent(destination)
            guard let followed = realLocation(of: next.standardizedFileURL, linksLeft: linksLeft - 1) else { return nil }
            base = followed
        } else {
            base = existing.resolvingSymlinksInPath().standardizedFileURL
        }
        for part in rest { base.appendPathComponent(part) }
        return base
    }
}

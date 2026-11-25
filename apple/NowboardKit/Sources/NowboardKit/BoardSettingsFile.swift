// The settings every device shares: `.nowboard.json` in the Tasks folder
// (spec 7, ADR 0011). It syncs with the tasks, so the iPhone and the Mac show
// the same categories. For now it holds only the categories.

import Foundation

/// A category as it's stored: the `area:` id, the name, a palette colour key.
public struct CategoryRecord: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var color: String

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

extension TaskFolder {
    public static let settingsFile = ".nowboard.json"

    private var settingsURL: URL { url.appendingPathComponent(Self.settingsFile) }

    /// The categories from `.nowboard.json`, or nil when there's no file or no
    /// non-empty list in it yet. A file that isn't valid JSON is an error, so
    /// nobody overwrites it.
    public func loadCategories() throws(TaskFileError) -> [CategoryRecord]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        let object = try settingsObject(data)
        // `as?` with a type: nil when the value is missing or isn't a list.
        guard let list = object["categories"] as? [Any],
            let json = try? JSONSerialization.data(withJSONObject: list),
            let cats = try? JSONDecoder().decode([CategoryRecord].self, from: json), !cats.isEmpty
        else { return nil }
        return cats
    }

    /// Writes the categories, keeping every other key in the file as it was.
    public func saveCategories(_ categories: [CategoryRecord]) throws(TaskFileError) {
        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            object = try settingsObject(data)
        }
        object["categories"] = categories.map { ["id": $0.id, "name": $0.name, "color": $0.color] }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw .io(error.localizedDescription)
        }
        try createFolder()
        try writeAtomically(String(decoding: data, as: UTF8.self) + "\n", to: settingsURL)
    }

    /// The file as a JSON object (`[String: Any]`: any value under each key).
    private func settingsObject(_ data: Data) throws(TaskFileError) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .invalidSettings
        }
        return object
    }
}

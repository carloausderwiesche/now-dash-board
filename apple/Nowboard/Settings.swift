// This device's settings: theme, compact cards, categories.
// With a Tasks folder, the categories come from its `.nowboard.json` (ADR
// 0011); the copy kept here is for the demo board and for starting that file.

import Foundation

struct DeviceSettings: Codable, Equatable {
    var theme = "braun"
    var compact = false
    var categories = Category.defaults

    private static let key = "settings"

    static func load() -> DeviceSettings {
        if let data = UserDefaults.standard.data(forKey: key),
            let saved = try? JSONDecoder().decode(DeviceSettings.self, from: data)
        {
            return saved
        }
        // First launch on a Mac: start from the Tauri app's settings, so both
        // apps look the same. (`?? DeviceSettings()` = the defaults otherwise.)
        return TauriSettings.read() ?? DeviceSettings()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Reads the Tauri app's settings.json, on macOS only, read-only.
enum TauriSettings {
    /// The parts of the Tauri file we use. `Decodable` fills it from JSON;
    /// fields that aren't listed here are ignored.
    private struct File: Decodable {
        var theme: String?
        var compact: Bool?
        var categories: [Category]?
    }

    static func read() -> DeviceSettings? {
        #if os(macOS)
            // The real home folder, from the user database (it would also be
            // right if the app were ever sandboxed again, ADR 0009).
            guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
            let url = URL(fileURLWithPath: String(cString: home))
                .appendingPathComponent("Library/Application Support/com.nestoririondo.nowboard/settings.json")
            guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else {
                return nil
            }
            var settings = DeviceSettings()
            if let theme = file.theme { settings.theme = theme }
            if let compact = file.compact { settings.compact = compact }
            if let cats = file.categories, !cats.isEmpty { settings.categories = cats }
            return settings
        #else
            return nil
        #endif
    }
}

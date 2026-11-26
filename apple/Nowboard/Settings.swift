// This device's settings: theme, card density, categories.
// With a Tasks folder, the categories come from its `.nowboard.json` (ADR
// 0011); the copy kept here is for the demo board and for starting that file.

import Foundation

/// How much room a card takes (Settings → Cards).
enum CardDensity: String, Codable, CaseIterable {
    case roomy, compact, minimal
}

struct DeviceSettings: Codable, Equatable {
    var theme = "braun"
    var density = CardDensity.roomy
    var categories = Category.defaults
    /// Where the `claude` command-line tool is, if it can't be found on its own
    /// (macOS only; there's no screen for it yet). Nil = look in the usual places.
    var claudePath: String?

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

// In an extension, so the plain `DeviceSettings()` stays available.
extension DeviceSettings {
    /// Settings saved before Minimal existed have `compact: true/false` instead of `density`.
    private enum Legacy: CodingKey { case compact }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: Legacy.self)
        theme = try c.decode(String.self, forKey: .theme)
        categories = try c.decode([Category].self, forKey: .categories)
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath)
        density = try c.decodeIfPresent(CardDensity.self, forKey: .density)
            ?? (try legacy.decodeIfPresent(Bool.self, forKey: .compact) == true ? .compact : .roomy)
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
            if file.compact == true { settings.density = .compact }
            if let cats = file.categories, !cats.isEmpty { settings.categories = cats }
            return settings
        #else
            return nil
        #endif
    }
}

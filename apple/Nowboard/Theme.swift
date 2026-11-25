// Every colour, radius and font of the app, ported from src/themes.ts.
// Views only use these tokens, never a colour of their own (CLAUDE.md).
// While both apps exist, src/themes.ts is the source for the Tauri app and
// this file for the Swift app; change both when a theme changes.

import CoreText
import SwiftUI

/// The theme families from DESIGN.md. They set radii and the font.
enum ThemeStyle {
    case rams, ive, pastel, eames
}

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let group: String
    let bg, surface, well, hover, ink, muted, line, accent, onAccent, scrim: Color
    let style: ThemeStyle
    let dark: Bool

    /// Small radius (buttons, dots' rings), large radius (panels), card radius.
    var radiusSmall: CGFloat { [.rams: 4, .ive: 10, .pastel: 10, .eames: 8][style]! }
    var radiusLarge: CGFloat { [.rams: 8, .ive: 20, .pastel: 18, .eames: 16][style]! }
    var radiusCard: CGFloat { [.rams: 4, .ive: 12, .pastel: 12, .eames: 10][style]! }

    /// The theme's font at a size and weight, the same one the Tauri app ends
    /// up with on a Mac: its CSS asks for Inter first, but Inter isn't
    /// installed, so Rams and Pastel fall back to Helvetica Neue. Ive is the
    /// system font (SF), Eames is Avenir Next. All of these ship with iOS too.
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        fontName.map { .custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight)
    }

    /// The font's family name; nil for the system font.
    var fontName: String? { [.eames: "Avenir Next", .rams: "Helvetica Neue", .pastel: "Helvetica Neue"][style] }

    /// How much to trim above and below a text line to get CSS's
    /// `line-height: <lineHeight>` (e.g. 0.8 for the big day number).
    /// SwiftUI always gives text the font's full height (ascent + descent);
    /// CSS centres the glyphs in a box of `lineHeight × size` instead. The
    /// font's real ascent and descent come from CoreText. Returns a negative
    /// padding for top and bottom.
    func lineBoxTrim(_ size: CGFloat, lineHeight: CGFloat, weight: Font.Weight = .semibold) -> CGFloat {
        let name: String =
            switch style {
            case .eames: "AvenirNext-DemiBold"
            case .rams, .pastel: "HelveticaNeue-Medium"
            case .ive: ".AppleSystemUIFont"
            }
        let ct = CTFontCreateWithName(name as CFString, size, nil)
        let full = CTFontGetAscent(ct) + CTFontGetDescent(ct)
        return -max(0, (full - lineHeight * size) / 2)
    }

    /// Letter spacing in CSS `em` (a share of the font size) → points.
    static func tracking(_ em: CGFloat, size: CGFloat) -> CGFloat { em * size }

    var colorScheme: ColorScheme { dark ? .dark : .light }

    static let all: [Theme] = [
        Theme(id: "braun", name: "Braun", group: "Rams", bg: "#ECEAE4", surface: "#F8F7F4", well: "#E0DDD5", hover: "rgba(0,0,0,.035)", ink: "#1B1B1A", muted: "#57554F", line: "#D5D2CA", accent: "#E5541B", onAccent: "#FFFFFF", scrim: "rgba(40,38,34,.28)", style: .rams, dark: false),
        Theme(id: "graphite", name: "Graphite", group: "Rams", bg: "#1D1D1C", surface: "#272725", well: "#2E2E2C", hover: "rgba(255,255,255,.04)", ink: "#EDEBE6", muted: "#A19F99", line: "#3B3A37", accent: "#F26B2F", onAccent: "#1D1D1C", scrim: "rgba(0,0,0,.5)", style: .rams, dark: true),
        Theme(id: "aluminium", name: "Aluminium", group: "Ive", bg: "#F5F5F7", surface: "#FFFFFF", well: "#E8E8ED", hover: "rgba(0,0,0,.035)", ink: "#1D1D1F", muted: "#5E5E63", line: "rgba(0,0,0,.09)", accent: "#0071E3", onAccent: "#FFFFFF", scrim: "rgba(245,245,247,.6)", style: .ive, dark: false),
        Theme(id: "spacegrey", name: "Space Grey", group: "Ive", bg: "#161617", surface: "#2C2C2E", well: "#2C2C2E", hover: "rgba(255,255,255,.05)", ink: "#F5F5F7", muted: "#A1A1A6", line: "rgba(255,255,255,.1)", accent: "#2997FF", onAccent: "#FFFFFF", scrim: "rgba(0,0,0,.45)", style: .ive, dark: true),
        Theme(id: "peach", name: "Peach", group: "Pastel", bg: "#FBF1EA", surface: "#FFFAF6", well: "#F3E3D8", hover: "rgba(0,0,0,.03)", ink: "#3B2A22", muted: "#5E4A3D", line: "#EEDDD1", accent: "#EE8E62", onAccent: "#3B2A22", scrim: "rgba(59,42,34,.18)", style: .pastel, dark: false),
        Theme(id: "lavender", name: "Lavender", group: "Pastel", bg: "#F1EEFA", surface: "#FBFAFF", well: "#E4DFF4", hover: "rgba(0,0,0,.03)", ink: "#2B2640", muted: "#524C6B", line: "#E2DCF3", accent: "#8B74E8", onAccent: "#FFFFFF", scrim: "rgba(43,38,64,.2)", style: .pastel, dark: false),
        Theme(id: "plywood", name: "Plywood", group: "Eames", bg: "#EFE6D6", surface: "#F8F2E7", well: "#E4D8C2", hover: "rgba(60,40,20,.04)", ink: "#2A2119", muted: "#5C4F42", line: "#DCCDB4", accent: "#C8431F", onAccent: "#FFFFFF", scrim: "rgba(42,33,25,.24)", style: .eames, dark: false),
        Theme(id: "walnut", name: "Walnut", group: "Eames", bg: "#271F19", surface: "#33291F", well: "#3B3026", hover: "rgba(255,240,220,.04)", ink: "#F2E7D5", muted: "#C2B19A", line: "#46392D", accent: "#F07A43", onAccent: "#271F19", scrim: "rgba(0,0,0,.5)", style: .eames, dark: true),
        Theme(id: "casestudy", name: "Case Study", group: "Eames", bg: "#F3F1EC", surface: "#FFFFFF", well: "#E6E3DC", hover: "rgba(0,0,0,.035)", ink: "#151413", muted: "#55524C", line: "#D9D5CC", accent: "#2352A3", onAccent: "#FFFFFF", scrim: "rgba(21,20,19,.26)", style: .eames, dark: false),
    ]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }
}

/// The 14 category colours: a strong one (dots) and a soft tint (Today cards),
/// for light and dark themes. In hue order, like the colour picker.
enum Palette: String, CaseIterable, Codable, Sendable {
    case rose, red, orange, amber, lime, green, teal, cyan, blue, indigo, violet, pink, brown, slate

    private var values: (light: (Color, Color), dark: (Color, Color)) {
        switch self {
        case .rose: (("#D6456C", "#F9DCE4"), ("#FF8FB0", "#46262F"))
        case .red: (("#D23B2E", "#F9DDD9"), ("#FF8A7F", "#47231F"))
        case .orange: (("#D2621A", "#FBE3D1"), ("#FFA466", "#46301C"))
        case .amber: (("#C98512", "#FAEBCB"), ("#FFC266", "#45361C"))
        case .lime: (("#6B8E12", "#E7F0CC"), ("#C2E26A", "#2F3A17"))
        case .green: (("#2E8B3E", "#D9EFDC"), ("#7FD98E", "#1D3A23"))
        case .teal: (("#138A7E", "#D3EFEA"), ("#6FE0CF", "#17383A"))
        case .cyan: (("#0E85A6", "#D2ECF3"), ("#6BD3F0", "#16343E"))
        case .blue: (("#2F6BDB", "#DCE7FB"), ("#7FAAFF", "#1F3050"))
        case .indigo: (("#4B4FC9", "#E0E1F8"), ("#9EA1FF", "#262850"))
        case .violet: (("#7A55D6", "#E6DDFA"), ("#B9A2FF", "#30284A"))
        case .pink: (("#C2408F", "#F7DCEC"), ("#FF8DD0", "#44253A"))
        case .brown: (("#8A5A3B", "#EEE2D8"), ("#D2A685", "#3A2C22"))
        case .slate: (("#5D6470", "#E3E5E9"), ("#B4BAC6", "#2C3038"))
        }
    }

    func strong(in theme: Theme) -> Color { theme.dark ? values.dark.0 : values.light.0 }
    func tint(in theme: Theme) -> Color { theme.dark ? values.dark.1 : values.light.1 }
}

// MARK: - Colours from CSS text

/// Lets the tables above write colours exactly as themes.ts does: `"#E5541B"`
/// or `"rgba(0,0,0,.035)"`.
///
/// Swift note: `ExpressibleByStringLiteral` means a plain string literal can
/// stand where a `Color` is expected, and Swift calls `init(stringLiteral:)`.
/// `extension` adds this to SwiftUI's own `Color` type.
extension Color: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral css: String) {
        if css.hasPrefix("#"), css.count == 7, let v = UInt32(css.dropFirst(), radix: 16) {
            self.init(.sRGB, red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
            return
        }
        if css.hasPrefix("rgba("), css.hasSuffix(")") {
            let parts = css.dropFirst(5).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 4 {
                self.init(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, opacity: parts[3])
                return
            }
        }
        assertionFailure("Not a colour: \(css)")
        self = .clear
    }
}

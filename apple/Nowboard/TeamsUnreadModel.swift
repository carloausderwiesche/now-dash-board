// The Teams unread box, the app's side: reading the Dock badge through the
// macOS Accessibility interface, and keeping the latest answer for the screen.
//
// The Dock draws the red badge on Teams' icon. The Accessibility interface lets
// one app ask another for what is on screen (it is what screen readers use),
// and the badge text is there as the Dock item's "status label". macOS only
// allows it after the person grants Accessibility in System Settings, and we
// never ask on our own: only the "Allow access" button does.

#if os(macOS)
    import AppKit
    import ApplicationServices
    import NowboardKit
    import Observation

    /// Reads Teams' Dock badge. A protocol, so tests use a fake instead of the real Dock.
    ///
    /// Swift note: `Sendable` = safe to use from background threads (it's called off the main thread).
    protocol DockBadgeReader: Sendable {
        /// Is Nowboard allowed to use the Accessibility interface? (Never shows a prompt.)
        func isAllowed() -> Bool
        /// Reads the badge. Slow (talks to another app): call it off the main thread.
        func read() -> DockBadgeReading
        /// Shows macOS's own "allow Accessibility" prompt. Only the "Allow access" button calls this.
        func requestAccess()
    }

    /// The real thing: asks the Dock process through the Accessibility interface.
    struct AccessibilityDockBadgeReader: DockBadgeReader {
        /// The ids Teams has had (the new one and the classic one).
        static let teamsBundleIDs = ["com.microsoft.teams2", "com.microsoft.teams"]

        func isAllowed() -> Bool { AXIsProcessTrusted() }

        func requestAccess() {
            // "Prompt" tells macOS to show its dialog that leads to the Accessibility settings.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        func read() -> DockBadgeReading {
            guard AXIsProcessTrusted() else { return .notAllowed }
            // (Asking per bundle id is safe from a background thread.)
            let running = Self.teamsBundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
            guard running else { return .notRunning }
            guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
                return .failed  // the Dock is restarting
            }
            let root = AXUIElementCreateApplication(dock.processIdentifier)
            // Don't wait the default six seconds per question if the Dock is busy.
            AXUIElementSetMessagingTimeout(root, 1)
            // The Dock's tree: the application → a list → one item per icon.
            guard case .value(let lists) = children(of: root) else { return .failed }
            for list in lists {
                guard case .value(let items) = children(of: list) else { continue }
                for item in items {
                    guard case .value(let title) = string(item, kAXTitleAttribute), Self.isTeams(title) else { continue }
                    // AXStatusLabel is the text of the red badge. "No such attribute" or "no value"
                    // means no badge; any other error means we don't know (not "nothing unread").
                    switch string(item, "AXStatusLabel") {
                    case .value(let text): return .label(text)
                    case .none: return .label(nil)
                    case .failed: return .failed
                    }
                }
            }
            return .notInDock
        }

        /// The Dock item's title for Teams: "Microsoft Teams" (also "Microsoft Teams (work or school)") or just "Teams".
        /// Not any title that merely contains "teams".
        static func isTeams(_ title: String) -> Bool {
            let t = title.lowercased().trimmingCharacters(in: .whitespaces)
            return t == "teams" || t.hasPrefix("microsoft teams")
        }

        /// What asking the Accessibility interface for something gave: a value, "there is none", or "it didn't work".
        private enum Answer<Value> {
            case value(Value)
            case none
            case failed
        }

        private func copy(_ element: AXUIElement, _ attribute: String) -> Answer<CFTypeRef> {
            var value: CFTypeRef?
            switch AXUIElementCopyAttributeValue(element, attribute as CFString, &value) {
            case .success: return value.map { .value($0) } ?? .none
            case .noValue, .attributeUnsupported: return .none
            default: return .failed
            }
        }

        private func children(of element: AXUIElement) -> Answer<[AXUIElement]> {
            switch copy(element, kAXChildrenAttribute) {
            case .value(let v): return .value((v as? [AXUIElement]) ?? [])
            case .none: return .value([])
            case .failed: return .failed
            }
        }

        private func string(_ element: AXUIElement, _ attribute: String) -> Answer<String> {
            switch copy(element, attribute) {
            case .value(let v): return (v as? String).map { .value($0) } ?? .none
            case .none: return .none
            case .failed: return .failed
            }
        }
    }

    /// The latest Teams status for the box. It looks every few seconds, only while the box is on screen.
    @MainActor @Observable
    final class TeamsUnreadModel {
        private(set) var status: TeamsStatus?
        /// How often to look, in seconds.
        static let interval: Double = 5

        @ObservationIgnored private let reader: any DockBadgeReader

        init(reader: any DockBadgeReader = AccessibilityDockBadgeReader()) {
            self.reader = reader
        }

        var display: TeamsDisplay? { status.map(TeamsDisplay.init) }

        /// Looks once, off the main thread (the Dock can be slow to answer), and keeps the answer.
        /// If a look is already under way this one does nothing, so an older answer can't overwrite
        /// a newer one. A look that got no answer (the Dock was busy) keeps what was shown before.
        func refresh() async {
            guard !looking else { return }
            looking = true
            defer { looking = false }
            let reader = reader
            let reading = await Task.detached(priority: .utility) { reader.read() }.value
            if let new = reading.status { status = new }
        }

        @ObservationIgnored private var looking = false
        @ObservationIgnored private var recheck: Task<Void, Never>?

        /// Looks now and then every few seconds, until the task is cancelled (the box leaves the screen).
        /// Then the old reading is forgotten, so coming back never shows a stale number.
        func poll() async {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
            status = nil
            recheck?.cancel()
        }

        /// The "Allow access" button: shows macOS's prompt, then looks again a moment later.
        func requestAccess() {
            reader.requestAccess()
            recheck?.cancel()
            recheck = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }

        /// Opens System Settings → Privacy & Security → Accessibility.
        func openSettings() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        #if DEBUG
            /// `-teamsDemo count|many|dot|zero|off|nodock|denied`: a fixed status for snapshots (no polling happens then).
            var isDemo: Bool { DebugSnapshot.argument("teamsDemo") != nil }

            func applyDebugArguments() {
                switch DebugSnapshot.argument("teamsDemo") {
                case "count": status = .unread(.count(3))
                case "many": status = .unread(.atLeast(99))
                case "dot": status = .unread(.unknown)
                case "zero": status = .unread(.none)
                case "off": status = .notRunning
                case "nodock": status = .notInDock
                case "denied": status = .notAllowed
                default: break
                }
            }
        #endif
    }
#endif

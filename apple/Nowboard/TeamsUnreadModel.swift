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
            let running = NSWorkspace.shared.runningApplications.contains { app in
                app.bundleIdentifier.map(Self.teamsBundleIDs.contains) ?? false
            }
            guard running else { return .notRunning }
            guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
                return .notInDock
            }
            let root = AXUIElementCreateApplication(dock.processIdentifier)
            // The Dock's tree: the application → a list → one item per icon.
            for list in children(of: root) {
                for item in children(of: list) {
                    guard let title = string(item, kAXTitleAttribute), title.lowercased().contains("teams") else { continue }
                    // AXStatusLabel is the text of the red badge; missing = no badge.
                    return .label(string(item, "AXStatusLabel"))
                }
            }
            return .notInDock
        }

        private func children(of element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
            return (value as? [AXUIElement]) ?? []
        }

        private func string(_ element: AXUIElement, _ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? String
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
        func refresh() async {
            let reader = reader
            let reading = await Task.detached(priority: .utility) { reader.read() }.value
            status = reading.status
        }

        /// Looks now and then every few seconds, until the task is cancelled (the box leaves the screen).
        func poll() async {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }

        /// The "Allow access" button: shows macOS's prompt, then looks again a moment later.
        func requestAccess() {
            reader.requestAccess()
            Task {
                try? await Task.sleep(for: .seconds(1))
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

// Debug builds only: renders the board to a PNG and quits. Used to compare
// the Swift app with the Tauri app without clicking through it:
//
//   Nowboard.app/Contents/MacOS/Nowboard -snapshot board.png -width 1190 -theme casestudy
//
// It prints where the PNG went (the app's temporary folder, because of the sandbox).
//
// On the simulator, pass the same arguments with `xcrun simctl launch`.
// `#if DEBUG` leaves this file out of release builds entirely.

#if DEBUG
    import SwiftUI

    enum DebugSnapshot {
        /// The value after `-name` in the launch arguments, if any.
        static func argument(_ name: String) -> String? {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-\(name)"), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        /// `-open <file name>` opens that card's panel, `-adding true` opens
        /// quick add, `-theme <id>` picks a theme: for screenshots of the panels.
        @MainActor
        static func applyLaunchState(store: BoardStore) {
            guard argument("snapshot") == nil else { return }
            if let theme = argument("theme") { store.settings.theme = theme }
            // `-demo true`: the demo board in memory; the saved folder is kept.
            if argument("demo") == "true" { store.useDemoForSnapshot() }
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                if let id = argument("open") { store.openID = id }
                if argument("adding") == "true" { store.adding = true }
                #if os(macOS)
                    // `-panel true`: open the ⌥ Space panel, as if the shortcut was pressed.
                    if argument("panel") == "true" { GlobalQuickAdd.shared.toggle() }
                #endif
            }
        }

        #if os(macOS)
            /// `-windowshot <name>`: after the board has loaded, captures the
            /// app's own window (real text fields, scroll view, title bar
            /// spacing) to the temp folder and quits. No Screen Recording
            /// permission needed: it's the app's own pixels.
            /// `-dragdemo <file name>` first drags that card a little, so the
            /// shot shows the drag (ghost, clone, cards moved aside).
            @MainActor
            static func windowShotIfAsked(store: BoardStore) {
                guard let name = argument("windowshot") else { return }
                // Window shots always use the demo board (in memory, the saved
                // folder is kept), so a scripted drag or drop can never touch
                // real task files.
                store.useDemoForSnapshot()
                Task { @MainActor in
                    await store.reload()
                    try? await Task.sleep(for: .seconds(2))
                    if let id = argument("dragdemo"), store.isDemo, let frame = store.drag.cardFrames[id] {
                        let start = CGPoint(x: frame.midX, y: frame.midY)
                        let dx = argument("dx").flatMap { Double($0) } ?? 0
                        let dy = argument("dy").flatMap { Double($0) } ?? 0
                        for step in 1...10 {
                            let t = Double(step) / 10
                            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
                            let status = store.task(id)?.status ?? .today
                            store.drag.moved(id, start: start, location: p, status: status)
                            try? await Task.sleep(for: .milliseconds(30))
                        }
                        try? await Task.sleep(for: .milliseconds(700))  // settle + slide animation
                        // `-drop true`: let go, like the mouse-up the event monitor handles.
                        if argument("drop") == "true", let d = store.drag.ended() {
                            store.drag.onDrop?(d.id, d.target)
                            try? await Task.sleep(for: .milliseconds(900))
                        }
                    }
                    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                        let view = window.contentView?.superview ?? window.contentView,
                        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                    else { exit(1) }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    print("snapshot:", url.path)
                    exit(0)
                }
            }
        #endif

        /// Renders and quits if the app was started with `-snapshot <path>`.
        @MainActor
        static func runIfAsked(store: BoardStore) {
            guard let path = argument("snapshot") else { return }
            if let theme = argument("theme") { store.settings.theme = theme }
            if argument("compact") == "true" { store.settings.compact = true }
            store.filter = argument("filter")
            if argument("demo") == "true" { store.useDemoForSnapshot() }
            let width = argument("width").flatMap { Double($0) } ?? 1190
            Task {
                await store.reload()
                // With `-open <file name>`: the detail panel instead of the board.
                let panelID = argument("open")
                let view = Group {
                    if let panelID {
                        DetailPanel(id: panelID, scrolls: false).frame(height: 900)
                    } else {
                        BoardContent(narrow: width < 640)
                    }
                }
                    .environment(store)
                    .frame(width: width)
                    .background(store.theme.bg)
                    .foregroundStyle(store.theme.ink)
                    .environment(\.colorScheme, store.theme.colorScheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                #if os(macOS)
                    let image = renderer.nsImage.flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                #else
                    let image = renderer.uiImage?.cgImage
                #endif
                // The sandbox only lets the app write inside its own container,
                // so the file goes to the app's temporary folder; its path is printed.
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
                print("snapshot:", url.path)
                if let image {
                    let rep = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
                    if let rep {
                        CGImageDestinationAddImage(rep, image, nil)
                        CGImageDestinationFinalize(rep)
                    }
                }
                exit(0)
            }
        }
    }
#endif

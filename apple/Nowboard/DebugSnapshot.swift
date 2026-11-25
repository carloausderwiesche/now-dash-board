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
                // `-settings true` opens settings, `-delete <file name>` deletes
                // that card (demo only), so the Undo pill shows.
                if argument("settings") == "true" { store.showingSettings = true }
                if let id = argument("delete"), store.isDemo { store.delete(id) }
                // `-menu <file name>`: that card's menu, as if right-clicked at its middle.
                if let id = argument("menu"), let f = store.drag.cardFrames[id] { store.menu = (id, CGPoint(x: f.midX, y: f.midY)) }
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
                    // `-finishdemo <file name>`: finish that card and capture the
                    // window during its flight into Done (0-name.png … 4-name.png).
                    if let id = argument("finishdemo"), store.isDemo {
                        let start = Date()
                        store.finish(id)
                        for (i, ms) in [300, 520, 640, 760, 1300].enumerated() {
                            // At least a frame's wait, so the window redraws between shots.
                            let wait = max(0.02, Double(ms) / 1000 - Date().timeIntervalSince(start))
                            try? await Task.sleep(for: .seconds(wait))
                            capture("\(i)-" + name)
                        }
                        exit(0)
                    }
                    // `-focusdemo <file name>`: focus that card and capture the
                    // window during the animation (name-0.png … name-6.png).
                    if let id = argument("focusdemo"), store.isDemo {
                        let start = Date()
                        store.toggleFocus(id)
                        for (i, ms) in [0, 60, 130, 200, 300, 420, 700].enumerated() {
                            let wait = Double(ms) / 1000 - Date().timeIntervalSince(start)
                            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                            capture("\(i)-" + name)
                        }
                        exit(0)
                    }
                    // `-todaydemo <file name>`: send that Backlog card to Today and
                    // capture the window during its flight (0-name.png … 5-name.png).
                    if let id = argument("todaydemo"), store.isDemo {
                        let start = Date()
                        store.moveToTop(id, of: .today)
                        for (i, ms) in [30, 110, 200, 300, 420, 700].enumerated() {
                            let wait = max(0.02, Double(ms) / 1000 - Date().timeIntervalSince(start))
                            try? await Task.sleep(for: .seconds(wait))
                            capture("\(i)-" + name)
                        }
                        exit(0)
                    }
                    // `-cmdkey <1–6>`: press ⌘ and that digit first, through the
                    // same path as a real key press (menu shortcuts, then the views).
                    if let key = argument("cmdkey"), let n = Int(key), (1...6).contains(n),
                        let window = NSApp.windows.first(where: { $0.isVisible && !($0 is QuickPanel) }),
                        let down = NSEvent.keyEvent(
                            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, characters: key,
                            charactersIgnoringModifiers: key, isARepeat: false, keyCode: [18, 19, 20, 21, 23, 22][n - 1])
                    {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.sendEvent(down)
                        try? await Task.sleep(for: .milliseconds(600))
                    }
                    capture(name)
                    exit(0)
                }
            }
        #endif

        #if os(macOS)
            /// Captures the app's window to the temp folder and prints the path.
            @MainActor
            static func capture(_ name: String) {
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is QuickPanel) }),
                    let view = window.contentView?.superview ?? window.contentView,
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("snapshot:", url.path)
            }
        #endif

        /// Renders and quits if the app was started with `-snapshot <path>`.
        @MainActor
        static func runIfAsked(store: BoardStore) {
            guard let path = argument("snapshot") else { return }
            if let theme = argument("theme") { store.settings.theme = theme }
            if let density = argument("density").flatMap(CardDensity.init) { store.settings.density = density }
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

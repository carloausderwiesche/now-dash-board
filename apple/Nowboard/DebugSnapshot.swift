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

        /// Renders and quits if the app was started with `-snapshot <path>`.
        @MainActor
        static func runIfAsked(store: BoardStore) {
            guard let path = argument("snapshot") else { return }
            if let theme = argument("theme") { store.settings.theme = theme }
            if argument("compact") == "true" { store.settings.compact = true }
            store.filter = argument("filter")
            let width = argument("width").flatMap { Double($0) } ?? 1190
            Task {
                await store.reload()
                let view = BoardContent(narrow: width < 640)
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

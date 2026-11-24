// The app's entry point. `@main` tells Swift to start here.

import SwiftUI

@main
struct NowboardApp: App {
    /// `@State` keeps the store alive as long as the app runs. Views below get
    /// it through `.environment(store)` and read it with `@Environment`.
    @State private var store = BoardStore()

    init() {
        #if DEBUG
            DebugSnapshot.runIfAsked(store: store)
            DebugSnapshot.applyLaunchState(store: store)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            BoardView()
                .environment(store)
        }
        #if os(macOS)
            // No title bar, like the Tauri app: the board runs to the top edge
            // and the window buttons float over it.
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1190, height: 900)
            .commands {
                // ⌘R reloads, like pull-to-refresh on the phone.
                CommandGroup(after: .toolbar) {
                    Button("Reload") { Task { await store.reload() } }
                        .keyboardShortcut("r")
                }
            }
        #endif
    }
}

// The app's entry point. `@main` tells Swift to start here.

import SwiftUI

@main
struct NowboardApp: App {
    /// `@State` keeps the store alive as long as the app runs. Views below get
    /// it through `.environment(store)` and read it with `@Environment`.
    @State private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            BoardView()
                .environment(store)
        }
        #if os(macOS)
            .defaultSize(width: 900, height: 820)
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

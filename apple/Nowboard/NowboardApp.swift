// The app's entry point. `@main` tells Swift to start here.

import SwiftUI

@main
struct NowboardApp: App {
    /// `@State` keeps the store alive as long as the app runs. Views below get
    /// it through `.environment(store)` and read it with `@Environment`.
    @State private var store = BoardStore()
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    init() {
        #if os(iOS)
            // Home Screen quick actions (FocusLive.swift).
            FocusLive.store = store
        #endif
        #if os(macOS)
            // ⌥ Space from any app opens quick add in a floating panel.
            GlobalQuickAdd.shared.start(store: store)
            // Right-click on a card opens the themed card menu.
            CardMenuMonitor.shared.start(store: store)
        #endif
        #if DEBUG
            #if os(macOS)
                // `-classifyDemo "text"`: one real classification, printed, then quit.
                DebugClassify.runIfAsked()
                // `-captureDemo "text"`: the whole pipeline on a throwaway vault, printed, then quit.
                DebugCapture.runIfAsked()
            #endif
            DebugSnapshot.runIfAsked(store: store)
            DebugSnapshot.applyLaunchState(store: store)
            #if os(macOS)
                DebugSnapshot.windowShotIfAsked(store: store)
            #endif
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
                // The Mac opens the Dashboard; the board is its Tasks page.
                DashboardRoot()
                    .environment(store)
            #else
                BoardView()
                    .environment(store)
            #endif
        }
        #if os(macOS)
            // No title bar, like the Tauri app: the board runs to the top edge
            // and the window buttons float over it.
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1728, height: 1117)
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

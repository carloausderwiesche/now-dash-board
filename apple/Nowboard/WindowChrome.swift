// The Mac window without its three round buttons (close, minimise, zoom).
// The title bar is already hidden (`.windowStyle(.hiddenTitleBar)`), so the
// content runs to the top edge. This hides the buttons too.
//
// Hiding is only a look: the window can still be closed, minimised and zoomed
// from the menus and with ⌘W, ⌘M and Control-⌘-F, because those work on the
// window's *abilities* (its style mask), which we don't touch. The strip at
// the top of the window still drags it around.

#if os(macOS)
    import AppKit
    import SwiftUI

    /// Put this in a view's `.background(...)`: it reaches the window the view is in and hides its buttons.
    ///
    /// Swift note: SwiftUI has no way to talk to the window itself, so we hand it
    /// a small AppKit view (`NSViewRepresentable` wraps an AppKit view for SwiftUI).
    /// An `NSView` gets told when it is put into a window (`viewDidMoveToWindow`):
    /// that's our moment to find the window.
    struct HideWindowButtons: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { Watcher() }
        func updateNSView(_ view: NSView, context: Context) {}

        final class Watcher: NSView {
            /// The notification listeners, replaced whenever the view moves to a window. (The app has
            /// one window and they only mention it, so there is nothing to clean up when it closes.)
            private var observers: [NSObjectProtocol] = []

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                guard let window else { return }
                Self.hideButtons(of: window)
                // AppKit shows the buttons again after some changes (leaving full screen, the
                // window coming back to the front), so hide them again when those happen.
                let names: [Notification.Name] = [
                    NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                    NSWindow.didResizeNotification, NSWindow.didDeminiaturizeNotification,
                ]
                observers = names.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { note in
                        guard let window = note.object as? NSWindow else { return }
                        MainActor.assumeIsolated { Watcher.hideButtons(of: window) }
                    }
                }
            }

            /// Hides the three buttons. Their window abilities (closable, miniaturizable, resizable) stay as they are.
            @MainActor static func hideButtons(of window: NSWindow) {
                for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    window.standardWindowButton(kind)?.isHidden = true
                }
            }
        }
    }
#endif

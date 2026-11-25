// Quick add from anywhere (Mac): ⌥ Space opens the quick-add box in a small
// see-through panel, a little above the middle of the screen under the mouse
// (DESIGN.md). It's a "non-activating" panel: you can type into it without
// the board window coming to the front. Return adds, Esc or a click
// elsewhere closes it.
//
// The shortcut uses Carbon's RegisterEventHotKey: the classic macOS API for
// global shortcuts. It needs no Accessibility permission and no dependency.
// Only one app can own ⌥ Space at a time, so quit the Tauri app (which
// registers the same shortcut) while trying this one.

#if os(macOS)
    import AppKit
    import Carbon.HIToolbox
    import SwiftUI

    @MainActor
    final class GlobalQuickAdd {
        static let shared = GlobalQuickAdd()

        private var store: BoardStore?
        private var panel: QuickPanel?
        private var hotKey: EventHotKeyRef?
        /// Whether ⌥ Space could be registered (false if another app owns it).
        private(set) var registered = false

        /// Registers ⌥ Space. Called once at launch.
        func start(store: BoardStore) {
            self.store = store
            guard hotKey == nil else { return }

            // Carbon calls a plain C function when a hot key is pressed. A C
            // function can't capture Swift values, so it just reaches for
            // `GlobalQuickAdd.shared` and hops to the main thread.
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in GlobalQuickAdd.shared.toggle() }
                return noErr
            }, 1, &spec, nil, nil)

            let id = EventHotKeyID(signature: OSType(0x4E4F5742), id: 1)  // "NOWB"
            let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
            registered = status == noErr
        }

        func toggle() {
            if let panel, panel.isVisible {
                close()
            } else {
                show()
            }
        }

        private func show() {
            guard let store else { return }
            let panel = self.panel ?? QuickPanel()
            self.panel = panel
            let view = QuickAdd(onClose: { [weak self] in self?.close() }, keys: panel.keys)
                .environment(store)
                .frame(width: 600)
                .clipShape(RoundedRectangle(cornerRadius: store.theme.radiusLarge))
                .overlay(RoundedRectangle(cornerRadius: store.theme.radiusLarge).strokeBorder(store.theme.line, lineWidth: 1))
                // In its own window the shadow must fit inside it (.quick-wrap.floating .quick).
                .cssShadow(y: 18, blur: 44, spread: -14, opacity: 0.4, radius: store.theme.radiusLarge)
                .padding(EdgeInsets(top: 24, leading: 40, bottom: 60, trailing: 40))
                .preferredColorScheme(store.theme.colorScheme)
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            let size = host.fittingSize

            // Centred on the screen under the mouse, a little above the middle.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let area = screen?.visibleFrame {
                panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY + area.height * 0.12 - size.height / 2,
                                      width: size.width, height: size.height), display: true)
            }
            // Fades in from slightly smaller, about 250ms, no bounce.
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-focusdebug") {
                    print("PANEL shown", panel.frame, "key:", panel.isKeyWindow, "visible:", panel.isVisible)
                }
            #endif
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 1
            }
        }

        func close() {
            panel?.orderOut(nil)
        }
    }

    /// A borderless, see-through panel that can take typing without activating the app.
    final class QuickPanel: NSPanel {
        init() {
            super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                       backing: .buffered, defer: true)
            isFloatingPanel = true
            level = .floating
            backgroundColor = .clear
            isOpaque = false
            hasShadow = false  // SwiftUI draws the shadow
            hidesOnDeactivate = false
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        }

        /// Where ⌘1–⌘6 go (the quick-add view listens here).
        let keys = QuickKeys()

        // A borderless panel can't become "key" (take typing) unless it says so.
        override var canBecomeKey: Bool { true }

        /// ⌘-keys arrive here first ("key equivalents"). ⌘1–⌘6 pick a category.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...6).contains(n)
            {
                keys.onCommandDigit?(n)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        // A click anywhere else takes the focus away: close, like the Tauri panel.
        override func resignKey() {
            super.resignKey()
            orderOut(nil)
        }
    }
#endif

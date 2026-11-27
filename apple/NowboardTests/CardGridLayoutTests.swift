// The card grid's layout, asked for sizes the way SwiftUI sometimes asks: with
// no width, an unlimited one, or none at all. It must give an answer, never crash.

#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Nowboard

    @MainActor
    private func fit(_ width: CGFloat, count: Int = 3) -> CGSize {
        let grid = CardGridLayout(minWidth: 200, spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in Color.clear.frame(height: 50) }
        }
        return NSHostingController(rootView: grid).sizeThatFits(in: CGSize(width: width, height: 1000))
    }

    @MainActor @Test func theGridMeasuresWithAnUnlimitedWidth() {
        // `Int(infinity)` used to crash here: the Dashboard's Today grid is measured this way.
        let size = fit(.infinity)
        #expect(size.width.isFinite && size.height.isFinite)
    }

    @MainActor @Test func theGridMeasuresWithNoRoomOrNoCards() {
        #expect(fit(0).height.isFinite)
        #expect(fit(1).height.isFinite)
        #expect(fit(800, count: 0).height == 0)
    }

    @MainActor @Test func theGridStillFlowsIntoColumnsAtANormalWidth() {
        // 3 cards of 50, min width 200, gap 12:
        // (Compared with a small tolerance: the layout works in fractions of a point.)
        #expect(abs(fit(1000).height - 50) < 0.5)  // five columns fit: one row
        #expect(abs(fit(600).height - 112) < 0.5)  // two columns: two rows and a gap
        #expect(abs(fit(200).height - 174) < 0.5)  // one column: three rows and two gaps
    }
#endif

#if os(macOS)
    // MARK: - The real click

    /// The Dashboard page on screen, a suggested task, and a click on "Today": the grid goes from an
    /// empty box to a card while SwiftUI is laying out. This used to crash on `Int(infinity)`.
    @MainActor @Test func sendingASuggestedTaskToTodayOnTheDashboardDoesNotCrash() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-grid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "---\nstatus: suggested\narea: work\n---\n".write(to: dir.appendingPathComponent("Call Mia.md"), atomically: true, encoding: .utf8)
        let store = BoardStore(testFolder: dir)
        await store.reload()
        let model = FocusSessionModel()
        model.attach(to: store)

        let host = NSHostingView(rootView: DashboardPageView().environment(store).environment(model).frame(width: 1400, height: 800))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        #expect(store.lists.suggested.count == 1)

        store.moveToTop("Call Mia.md", of: .today)
        try await Task.sleep(for: .milliseconds(1200))
        await store.waitForWrites()
        #expect(store.lists.today.map(\.id) == ["Call Mia.md"])
    }
#endif

#if os(macOS)
    // MARK: - The window's buttons

    /// The three round buttons are hidden, but the window can still be closed, minimised and zoomed
    /// (⌘W, ⌘M, Control-⌘-F work on these abilities).
    @MainActor @Test func theWindowButtonsAreHiddenButTheWindowKeepsItsAbilities() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Color.clear.background(HideWindowButtons()))
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            #expect(window.standardWindowButton(kind)?.isHidden == true)
        }
        #expect(window.styleMask.contains(.closable) && window.styleMask.contains(.miniaturizable) && window.styleMask.contains(.resizable))
        // AppKit shows them again: they are hidden again when the window next becomes key.
        window.standardWindowButton(.closeButton)?.isHidden = false
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
    }
#endif

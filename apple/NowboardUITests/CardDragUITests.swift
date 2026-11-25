import XCTest

final class CardDragUITests: XCTestCase {
    @MainActor
    func testATodayCardMovesWithAQuickSwipe() {
        let app = launch()
        swipe(card("Homepage copy review", in: app), below: card("Prep notes for 1-on-1", in: app), hold: 0.05, velocity: .slow)
    }

    @MainActor
    func testATodayCardMovesWithAFastSwipe() {
        let app = launch()
        swipe(card("Homepage copy review", in: app), below: card("Prep notes for 1-on-1", in: app), hold: 0, velocity: .fast)
    }

    @MainActor
    func testTheFocusCardMovesWithAQuickSwipe() {
        let app = launch()
        swipe(card("Review PR for alert thresholds", in: app), below: card("Homepage copy review", in: app), hold: 0.05, velocity: .slow)
    }

    @MainActor
    func testACardSentToTodayCanBeDraggedRightAway() {
        let app = launch()
        let moving = card("Write ADR on the message broker", in: app)
        scroll(app, from: 0.8, to: 0.2)
        // The card's own "Today ↑": the first one under its title, in its column.
        let send = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).allElementsBoundByIndex
            .filter { $0.frame.midX > moving.frame.minX && $0.frame.midX < moving.frame.maxX + 40 && $0.frame.minY > moving.frame.minY }
            .min { $0.frame.minY < $1.frame.minY }
        XCTAssertNotNil(send)
        send?.tap()
        sleep(1)
        scroll(app, from: 0.2, to: 0.9)
        scroll(app, from: 0.2, to: 0.9)
        XCTAssertLessThan(moving.frame.minY, card("Homepage copy review", in: app).frame.minY, "not sent to Today")
        swipe(moving, below: card("Homepage copy review", in: app), hold: 0.05, velocity: .slow)
    }

    @MainActor
    func testTheAppIconOffersToFinishTheFocusedTask() {
        let app = XCUIApplication()
        app.launchArguments = ["-livedemo", "true"]
        app.launch()
        XCTAssertTrue(card("Review PR for alert thresholds", in: app).waitForExistence(timeout: 10))
        // Twice: the second press leaves icon editing, if a run left it on.
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Nowboard"]
        for _ in 0..<3 where !icon.isHittable { springboard.swipeLeft() }
        icon.press(forDuration: 0.8)
        XCTAssertTrue(springboard.buttons["New task"].waitForExistence(timeout: 5))
        springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark done'")).firstMatch.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        // Done's "Last:" names the task once it's finished.
        let done = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Last: Review PR for alert thresholds'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch() -> XCUIApplication {
        // A fresh install has no folder, so it shows the demo board.
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(card("Homepage copy review", in: app).waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func swipe(_ moving: XCUIElement, below target: XCUIElement, hold: TimeInterval, velocity: XCUIGestureVelocity,
                       line: UInt = #line) {
        XCTAssertLessThan(moving.frame.minY, target.frame.minY, line: line)
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: hold, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
                   withVelocity: velocity, thenHoldForDuration: 0.4)
        let below = expectation(for: NSPredicate { _, _ in moving.frame.minY > target.frame.minY }, evaluatedWith: nil)
        wait(for: [below], timeout: 3)
    }

    /// Scrolls with a swipe in the left margin: a swipe on a card would move it.
    @MainActor
    private func scroll(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: from))
            .press(forDuration: 0, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: to)))
        sleep(1)
    }

    @MainActor
    private func card(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
}

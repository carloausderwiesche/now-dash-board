import XCTest

final class NotesUITests: XCTestCase {
    @MainActor
    func testTappingOutsideTheNotesShowsThemRendered() {
        let app = XCUIApplication()
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Homepage copy review'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let placeholder = app.staticTexts["Anything worth remembering"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        placeholder.tap()
        app.typeText("Hello **world**")
        app.staticTexts["Checklist"].tap()

        XCTAssertTrue(app.staticTexts["Hello world"].waitForExistence(timeout: 3), "the notes are still being edited")
    }
}

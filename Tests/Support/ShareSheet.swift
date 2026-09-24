import XCTest

extension XCUIApplication {
    /// Share extensions sit in the app row; action extensions sit in the list with ChatGPT/Gemini.
    func tapQueepShare() {
        let action = buttons["Salvar no Queep"]
        if action.waitForExistence(timeout: 4) {
            action.tap()
            return
        }
        let named = cells.matching(NSPredicate(format: "label CONTAINS 'Queep'")).firstMatch
        if named.waitForExistence(timeout: 4) {
            named.tap()
            return
        }
        let cell = cells["Queep"]
        XCTAssertTrue(cell.waitForExistence(timeout: 8), debugDescription)
        if cell.images["activityImageView"].exists {
            cell.images["activityImageView"].tap()
        } else {
            cell.tap()
        }
    }
}

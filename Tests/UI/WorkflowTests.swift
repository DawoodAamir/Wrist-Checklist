import XCTest

@MainActor final class WorkflowTests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  func testAddCompleteAndReopen() {
    let app = XCUIApplication()
    app.launchEnvironment["CHECKLIST_TEST_STORE"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 20), app.debugDescription)
    app.buttons["addTask"].tap()
    #if os(watchOS)
      XCTAssertTrue(app.buttons["Check equipment"].waitForExistence(timeout: 10))
      app.buttons["Check equipment"].tap()
      for _ in 0..<4 where !app.buttons["Add"].isHittable { app.swipeUp() }
    #else
      let title = app.textFields["taskTitle"]
      XCTAssertTrue(title.waitForExistence(timeout: 10))
      title.tap()
      title.typeText("Check equipment")
    #endif
    app.buttons["Add"].tap()
    let complete = app.buttons["Complete: Check equipment"]
    XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
    complete.tap()
    XCTAssertTrue(app.buttons["Mark incomplete: Check equipment"].waitForExistence(timeout: 10))
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["Mark incomplete: Check equipment"].waitForExistence(timeout: 15))
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Completed checklist"
    image.lifetime = .keepAlways
    add(image)
  }
}

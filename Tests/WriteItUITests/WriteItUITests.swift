import XCTest

@MainActor
final class WriteItUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "com.gongahkia.writeit")
    app.launchEnvironment["WRITEIT_UI_TESTING"] = "1"
    app.launchEnvironment["WRITEIT_UI_RESET"] = "1"
    app.launch()
  }

  func testOnboardingCompletes() throws {
    completeOnboarding()
    XCTAssertTrue(app.staticTexts["Write anywhere"].waitForExistence(timeout: 3))
  }

  func testOnboardingResumesAfterInterruption() throws {
    advance(to: "Choose a shortcut")
    advance(to: "Choose delivery")
    app.terminate()
    app.launchEnvironment["WRITEIT_UI_RESET"] = "0"
    app.launch()
    XCTAssertTrue(app.staticTexts["Choose delivery"].waitForExistence(timeout: 3))
  }

  func testCaptureReviewDeliveryFallbackAndUndo() throws {
    completeOnboarding()
    app.buttons["capture.testReview"].click()
    XCTAssertTrue(app.buttons["capture.insert"].waitForExistence(timeout: 3))
    app.buttons["capture.insert"].click()
    XCTAssertTrue(app.buttons["capture.undo"].waitForExistence(timeout: 3))
    app.buttons["capture.undo"].click()
  }

  func testCustomModelInvalidSourceShowsError() throws {
    completeOnboarding()
    app.buttons["capture.openModels"].click()
    app.buttons["models.tab.custom"].click()
    let field = app.textFields["models.customURL"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.click()
    field.typeText("https://")
    app.buttons["models.refresh"].click()
    XCTAssertTrue(app.staticTexts["Enter a valid public HTTPS manifest URL."].waitForExistence(timeout: 3))
  }

  func testProfileOutputOverrideControlIsAvailable() throws {
    completeOnboarding()
    app.buttons["capture.openModels"].click()
    app.buttons["models.tab.cloud"].click()
    app.buttons["Add current app profile"].click()
    XCTAssertTrue(app.popUpButtons["profile.outputStrategy"].waitForExistence(timeout: 3))
  }

  private func completeOnboarding() {
    advance(to: "Choose a shortcut")
    advance(to: "Choose delivery")
    advance(to: "Choose recognition")
    advance(to: "Review cloud privacy")
    let acknowledgement = app.buttons["I understand"]
    XCTAssertTrue(acknowledgement.waitForExistence(timeout: 5))
    acknowledgement.click()
    advance(to: "Set up local recognition")
    app.buttons["onboarding.continue"].click()
  }

  private func advance(to title: String) {
    app.buttons["onboarding.continue"].click()
    XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
  }
}

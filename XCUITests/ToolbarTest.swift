/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest

let website1: [String: String] = ["url": path(forTestPage: "test-mozilla-org.html"), "label": "Internet for people, not profit — Mozilla", "value": "localhost", "longValue": "localhost:\(serverPort)/test-fixture/test-mozilla-org.html"]
let website2 = path(forTestPage: "test-example.html")

let PDFWebsite = ["url": "http://www.pdf995.com/samples/pdf.pdf"]

class ToolbarTests: BaseTestCase {
    override func setUp() {
        super.setUp()
        XCUIDevice.shared.orientation = UIDeviceOrientation.landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = UIDeviceOrientation.portrait
        super.tearDown()
    }

    /**
     * Tests landscape page navigation enablement with the URL bar with tab switching.
     */
    func testLandscapeNavigationWithTabSwitch() {
        let urlPlaceholder = "Search or enter address"
        XCTAssert(app.textFields["url"].exists)
        let defaultValuePlaceholder = app.textFields["url"].placeholderValue!

        // Check the url placeholder text and that the back and forward buttons are disabled
        XCTAssertTrue(urlPlaceholder == defaultValuePlaceholder, "The placeholder does not show the correct value")
        XCTAssertFalse(app.buttons["Back"].isEnabled)
        XCTAssertFalse(app.buttons["Forward"].isEnabled)

        // Navigate to two pages and press back once so that all buttons are enabled in landscape mode.
        navigator.openURL(website1["url"]!)
        waitUntilPageLoad()
        waitForExistence(app.webViews.links["Mozilla"], timeout: 10)
        let valueMozilla = app.textFields["url"].value as! String
        XCTAssertEqual(valueMozilla, "localhost")
        XCTAssertTrue(app.buttons["Back"].isEnabled)
        XCTAssertFalse(app.buttons["Forward"].isEnabled)
        XCTAssertTrue(app.buttons["TabLocationView.reloadButton"].isEnabled)

        navigator.openURL(website2)
        waitUntilPageLoad()
        waitForValueContains(app.textFields["url"], value: "localhost")
        XCTAssertTrue(app.buttons["Back"].isEnabled)
        XCTAssertFalse(app.buttons["Forward"].isEnabled)

        app.buttons["Back"].tap()
        XCTAssertEqual(valueMozilla, "localhost")

        waitUntilPageLoad()
        XCTAssertTrue(app.buttons["Back"].isEnabled)
        XCTAssertTrue(app.buttons["Forward"].isEnabled)

        // Open new tab and then go back to previous tab to test navigation buttons.
        waitForTabsButton()
        navigator.goto(TabTray)
        waitForExistence(app.cells.staticTexts[website1["label"]!])
        app.cells.staticTexts[website1["label"]!].tap()
        XCTAssertEqual(valueMozilla, "localhost")

        // Test to see if all the buttons are enabled then close tab.
        waitUntilPageLoad()
        XCTAssertTrue(app.buttons["Back"].isEnabled)
        XCTAssertTrue(app.buttons["Forward"].isEnabled)

        navigator.nowAt(BrowserTab)
        waitForTabsButton()
        navigator.goto(TabTray)

        waitForExistence(app.cells.staticTexts[website1["label"]!])
        app.collectionViews.cells.element(boundBy: 0).buttons["closeTabButtonTabTray"].tap()

        // Go Back to other tab to see if all buttons are disabled.
        navigator.nowAt(BrowserTab)
        XCTAssertFalse(app.buttons["Back"].isEnabled)
        XCTAssertFalse(app.buttons["Forward"].isEnabled)
    }

    func testClearURLTextUsingBackspace() {
        navigator.openURL(website1["url"]!)
        waitUntilPageLoad()
        waitForTabsButton()
        waitForExistence(app.webViews.links["Mozilla"], timeout: 10)
        let valueMozilla = app.textFields["url"].value as! String
        XCTAssertEqual(valueMozilla, "localhost")

        // Simulate pressing on backspace key should remove the text
        app.textFields["url"].tap()
        app.textFields["address"].typeText("\u{8}")

        let value = app.textFields["address"].value
        XCTAssertEqual(value as? String, "", "The url has not been removed correctly")
    }

    // Check that after scrolling on a page, the URL bar is hidden. Tapping one on the status bar will reveal the URL bar, tapping again on the status will scroll to the top
    func testRevealToolbarWhenTappingOnStatusbar() {
        // Workaround when testing on iPhone. If the orientation is in landscape on iPhone the tests will fail.
        if !iPad() {
            XCUIDevice.shared.orientation = UIDeviceOrientation.portrait
            waitForExistence(app.otherElements["Navigation Toolbar"])
        }
        navigator.openURL(website1["url"]!, waitForLoading: true)
        // Adding the waiter right after navigating to the webpage in order to make the test more stable
        waitUntilPageLoad()
        waitForExistence(app.buttons["TabLocationView.shareButton"], timeout: 10)
        let shareButton = app.buttons["TabLocationView.shareButton"]
        let statusbarElement: XCUIElement = {
            if #available(iOS 13, *) {
                return XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
            } else {
                return app.statusBars.children(matching: .other).element.children(matching: .other).element(boundBy: 0)
            }
        }()
        app.swipeUp()
        XCTAssertFalse(shareButton.exists)
        statusbarElement.tap(force: true)
        XCTAssertTrue(shareButton.isHittable)
        statusbarElement.tap(force: true)
        let topElement = app.webViews.otherElements["Internet for people, not profit — Mozilla"].children(matching: .other).matching(identifier: "navigation").element(boundBy: 0).staticTexts["Mozilla"]
        waitForExistence(topElement, timeout: 10)
        XCTAssertTrue(topElement.isHittable)
    }
}

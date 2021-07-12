// Copyright Neeva. All rights reserved.

import Foundation
@testable import Client

class KeyboardShortcutTests: KIFTestCase {
    var bvc: BrowserViewController!
    
    override func setUp() {
        BrowserUtils.dismissFirstRunUI(tester())
        bvc = BrowserViewController.foregroundBVC()
    }

    func reset(tester: KIFUITestActor) {
        bvc.tabManager.removeAllTabsAndAddNormalTab()
    }

    func openTab(tester: KIFUITestActor) {
        tester.waitForAnimationsToFinish()

        if tester.viewExistsWithLabel("Cancel") {
            tester.tapView(withAccessibilityLabel: "Cancel")
        }

        tester.tapView(withAccessibilityLabel: "Show Tabs")
        tester.tapView(withAccessibilityLabel: "Add Tab")

        BrowserUtils.enterUrlAddressBar(tester, typeUrl: "www.neeva.com")
    }

    func openMultipleTabs(tester: KIFUITestActor) {
        for _ in 0...3 {
            openTab(tester: tester)
        }
    }

    func previousTab(tester: KIFUITestActor) {
        openTab(tester: tester)
        bvc.previousTabKeyCommand()
    }

    func testReloadTab() {
        reset(tester: tester())
        openTab(tester: tester())
        bvc.reloadTabKeyCommand()
    }

    // MARK: Navigation Tests
    func goBack() {
        openTab(tester: tester())
        BrowserUtils.enterUrlAddressBar(tester(), typeUrl: "www.google.com")
        bvc.goBackKeyCommand()
    }

    func testGoBack() {
        reset(tester: tester())
        goBack()
    }

    func testGoForward() {
        reset(tester: tester())
        goBack()
        bvc.goForwardKeyCommand()
    }

    // MARK: Find in Page
    func testFindInPageKeyCommand() {
        reset(tester: tester())
        openTab(tester: tester())
        bvc.findInPageKeyCommand()
    }

    // MARK: UI
    func testSelectLocationBarKeyCommand() {
        reset(tester: tester())
        bvc.selectLocationBarKeyCommand()
    }

    func testShowTabTrayKeyCommand() {
        reset(tester: tester())
        bvc.showTabTrayKeyCommand()
        XCTAssert(tester().viewExistsWithLabel("Add Tab"))
    }

    // MARK: Tab Mangement
    func testNewTabKeyCommand() {
        reset(tester: tester())
        bvc.newTabKeyCommand()
        XCTAssert(bvc.tabManager.tabs.count == 2)
    }

    func testNewPrivateTabKeyCommand() {
        reset(tester: tester())
        bvc.newPrivateTabKeyCommand()

        XCTAssert(bvc.tabManager.tabs.count == 2)
        XCTAssert(bvc.tabManager.selectedTab?.isPrivate == true)
    }

    func testCloseTabKeyCommand() {
        reset(tester: tester())
        openTab(tester: tester())

        XCTAssert(bvc.tabManager.tabs.count == 2)
        bvc.closeTabKeyCommand()
        XCTAssert(bvc.tabManager.tabs.count == 1)
    }

    func testNextTabKeyCommand() {
        reset(tester: tester())
        previousTab(tester: tester())
        bvc.nextTabKeyCommand()
        XCTAssert(bvc.tabManager.selectedTab == bvc.tabManager.tabs[1])
    }

    func testPreviousTabCommand() {
        reset(tester: tester())
        previousTab(tester: tester())
        XCTAssert(bvc.tabManager.selectedTab == bvc.tabManager.tabs[0])
    }

    func testCloseAllTabKeyCommand() {
        reset(tester: tester())
        openTab(tester: tester())
        bvc.closeTabKeyCommand()
        XCTAssert(bvc.tabManager.tabs.count == 1)
    }

    func testCloseAllTabsCommand() {
        reset(tester: tester())
        openMultipleTabs(tester: tester())
        bvc.closeAllTabsCommand()
        XCTAssert(bvc.tabManager.tabs.count == 1)
    }

    func testRestoreTabKeyCommand() {
        reset(tester: tester())
        openMultipleTabs(tester: tester())

        BrowserUtils.closeAllTabs(tester())
        tester().waitForAnimationsToFinish()

        bvc.restoreTabKeyCommand()

        XCTAssert(bvc.tabManager.tabs.count > 1)
    }
}
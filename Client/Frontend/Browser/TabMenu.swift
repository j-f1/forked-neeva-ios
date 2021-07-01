// Copyright Neeva. All rights reserved.

import UIKit
import Shared

class TabMenu {
    var tabManager: TabManager
    var neevaHomeViewController: NeevaHomeViewController?
    var alertPresentViewController: UIViewController?

    var tabsClosed: ((Bool) -> ())?

    // MARK: Close All Tabs
    func showConfirmCloseAllTabs(numberOfTabs: Int) {
        let isPrivate = tabManager.selectedTab?.isPrivate ?? false
        guard let alertPresentViewController = alertPresentViewController else {
            return
        }

        let actionSheet = UIAlertController(title: nil, message: "Are you sure you want to close all open \(isPrivate ? "private " : "")tabs?", preferredStyle: .actionSheet)
        
        let closeAction = UIAlertAction(title: "Close \(numberOfTabs) \(isPrivate ? "Private " : "")Tabs", style: .destructive) { [self] _ in
            if isPrivate {
                _ = tabManager.switchPrivacyMode()

                // wait for tabManager to switch to normal mode before closing private tabs
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    tabManager.removeTabsAndAddNormalTab(tabManager.privateTabs, showToast: false)
                    neevaHomeViewController?.homeViewModel.isPrivate = tabManager.selectedTab!.isPrivate
                }
            } else {
                tabManager.removeTabsAndAddNormalTab(tabManager.normalTabs, showToast: false)
            }

            if let tabsClosed = tabsClosed {
                tabsClosed(isPrivate)
            }
        }
        closeAction.accessibilityLabel = "Confirm Close All Tabs"

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        // add all actions to alert
        actionSheet.addAction(closeAction)
        actionSheet.addAction(cancelAction)
        // show the alert
        alertPresentViewController.present(actionSheet, animated: true, completion: nil)
    }

    func createCloseAllTabsAction() -> UIAction {
        let action = UIAction(title: "Close All Tabs", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            // make sure the user really wants to close all tabs
            self.showConfirmCloseAllTabs(numberOfTabs: self.getTabCountForCurrentType())
        }
        action.accessibilityLabel = "Close All Tabs"

        return action
    }

    func createCloseAllTabsMenu() -> UIMenu {
        return UIMenu(sections: [[createCloseAllTabsAction()]])
    }

    func getTabCountForCurrentType() -> Int {
        let isPrivate = tabManager.selectedTab?.isPrivate ?? false

        if isPrivate {
            return tabManager.privateTabs.count
        } else {
            return tabManager.normalTabs.count
        }
    }

    // MARK: Recently Closed Tabs
    func createRecentlyClosedTabsMenu() -> UIMenu {
        let recentlyClosed = tabManager.recentlyClosedTabs.filter {
            !InternalURL.isValid(url: ($0.url ?? URL(string: "")))
        }

        var actions = [UIAction]()
        for tab in recentlyClosed {
            let action = UIAction(title: tab.title ?? "Untitled", discoverabilityTitle: tab.url?.absoluteString) { _ in
                _ = self.tabManager.restoreSavedTabs([tab])
            }
            action.accessibilityLabel = tab.title ?? "Untitled"
            actions.append(action)
        }

        return UIMenu(title: "Recently Closed", children: actions)
    }

    init(tabManager: TabManager, neevaHomeViewController: NeevaHomeViewController? = nil, alertPresentViewController: UIViewController? = nil) {
        self.tabManager = tabManager
        self.neevaHomeViewController = neevaHomeViewController
        self.alertPresentViewController = alertPresentViewController
    }
}

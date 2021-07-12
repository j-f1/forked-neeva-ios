// Copyright Neeva. All rights reserved.

import Shared
import Storage
import SFSafeSymbols

extension BrowserViewController: LegacyURLBarDelegate {
    func urlBarDidPressReload(_ urlBar: LegacyURLBarView) {
        // log tap reload
        ClientLogger.shared.logCounter(.TapReload, attributes: EnvironmentHelper.shared.getAttributes())

        tabManager.selectedTab?.reload()
    }

    func urlBarNeevaMenu(_ urlBar: LegacyURLBarView, from button: UIButton){
        if TourManager.shared.userReachedStep(tapTarget: .neevaMenu) == .resumeAction {
            self.dismiss(animated: true, completion: nil)
        }

        let isPrivate = tabManager.selectedTab?.isPrivate ?? false
        let host = PopOverNeevaMenuViewController(
            delegate: self,
            source: button, isPrivate: isPrivate,
            feedbackImage: screenshot())
        self.popOverNeevaMenuViewController = host
        // log tap neeva menu
        ClientLogger.shared.logCounter(.OpenNeevaMenu, attributes: EnvironmentHelper.shared.getAttributes())

        //Fix autolayout sizing
        host.view.backgroundColor = UIColor.PopupMenu.background
        host.preferredContentSize = host.sizeThatFits(in: CGSize(width: 340, height: 315))
        present(
            host,
            animated: true,
            completion: nil)
    }

    func neevaMenuDidRequestToOpenPage(page: NeevaMenuButtonActions) {
        switch(page){
        case .home:
            switchToTabForURLOrOpen(NeevaConstants.appHomeURL)
            break
        case .spaces:
            switchToTabForURLOrOpen(NeevaConstants.appSpacesURL)
            break
        default:
            break
        }
    }

    func urlBarDidTapShield(_ urlBar: LegacyURLBarView, from button: UIButton) {
        let host = PopOverTrackingMenuViewController(
            delegate: self,
            source: button)

        // log tap shield
        ClientLogger.shared.logCounter(.OpenShield, attributes: EnvironmentHelper.shared.getAttributes())

        //Fix autolayout sizing
        host.view.backgroundColor = UIColor.PopupMenu.background
        host.preferredContentSize = host.sizeThatFits(in: CGSize(width: 340, height: 120))
        present(
            host,
            animated: true,
            completion: nil)
    }

    func urlBarDidPressStop(_ urlBar: LegacyURLBarView) {
        tabManager.selectedTab?.stop()
    }

    func urlBarDidPressTabs(_ urlBar: LegacyURLBarView) {
        showTabTray()
    }

    func urlBarReloadMenu(_ urlBar: LegacyURLBarView) -> UIMenu? {
        guard
            let tab = tabManager.selectedTab,
            tab.webView?.url != nil,
            (tab.getContentScript(name: ReaderMode.name()) as? ReaderMode)?.state != .active
        else { return nil }

        let toggleActionTitle: String
        let iconName: SFSymbol

        let willSwitchToMobile = UserAgent.isDesktop(ua: UserAgent.getUserAgent()) ? !tab.changedUserAgent : tab.changedUserAgent
        if willSwitchToMobile {
            toggleActionTitle = Strings.AppMenuViewMobileSiteTitleString
            let hasHomeButton = UIConstants.safeArea.bottom == 0
            iconName = hasHomeButton ? .iphoneHomebutton : .iphone
        } else {
            toggleActionTitle = Strings.AppMenuViewDesktopSiteTitleString
            iconName = .laptopcomputer
        }
        return UIMenu(
            children: [
                UIAction(title: toggleActionTitle, image: UIImage(systemSymbol: iconName)) { _ in
                    if let url = tab.url {
                        tab.toggleChangeUserAgent()
                        Tab.ChangeUserAgent.updateDomainList(forUrl: url, isChangedUA: tab.changedUserAgent, isPrivate: tab.isPrivate)
                    }
                }
            ]
        )
    }

    func locationActionsForURLBar(_ urlBar: LegacyURLBarView) -> [AccessibleAction] {
        if UIPasteboard.general.string != nil {
            return [pasteGoAction, pasteAction, copyAddressAction]
        } else {
            return [copyAddressAction]
        }
    }

    func urlBarDidLongPressLegacyLocation(_ urlBar: LegacyURLBarView) {
        let urlActions = self.getLegacyLongPressLocationBarActions(with: urlBar, webViewContainer: self.webViewContainer)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        self.presentSheetWith(actions: [urlActions], on: self, from: urlBar)
    }

    func urlBarLocationAccessibilityActions(_ urlBar: LegacyURLBarView) -> [UIAccessibilityCustomAction]? {
        return locationActionsForURLBar(urlBar).map { $0.accessibilityCustomAction }
    }

    func urlBar(_ urlBar: LegacyURLBarView, didRestoreText text: String) {
        _urlBarUpdateSearchController(for: text)
        legacyURLBar.historySuggestionModel.setQueryWithoutAutocomplete(text)
    }

    func urlBar(didEnterText text: String) {
        _urlBarUpdateSearchController(for: text)
    }

    func urlBar(didSubmitText text: String) {
        guard let currentTab = tabManager.selectedTab else { return }

        if let fixupURL = URIFixup.getURL(text) {
            // The user entered a URL, so use it.
            finishEditingAndSubmit(fixupURL, visitType: VisitType.typed, forTab: currentTab)
            return
        }

        // We couldn't build a URL, so check for a matching search keyword.
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard trimmedText.firstIndex(of: " ") != nil else {
            submitSearchText(text, forTab: currentTab)
            return
        }

        self.submitSearchText(text, forTab: currentTab)
    }

    fileprivate func submitSearchText(_ text: String, forTab tab: Tab) {

        if let searchURL = neevaSearchEngine.searchURLForQuery(text) {
            // We couldn't find a matching search keyword, so do a search query.
            finishEditingAndSubmit(searchURL, visitType: VisitType.typed, forTab: tab)
        } else {
            // We still don't have a valid URL, so something is broken. Give up.
            print("Error handling URL entry: \"\(text)\".")
            assertionFailure("Couldn't generate search URL: \(text)")
        }
    }

    func urlBarDidBeginDragInteraction(_ urlBar: LegacyURLBarView) {
        dismissVisibleMenus()
    }
}

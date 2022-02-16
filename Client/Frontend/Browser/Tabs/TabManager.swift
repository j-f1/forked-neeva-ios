/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Combine
import Defaults
import Foundation
import Shared
import Storage
import WebKit
import XCGLogger

private let log = Logger.browser

protocol TabManagerDelegate: AnyObject {
    func tabManager(
        _ tabManager: TabManager, didSelectedTabChange selected: Tab?, previous: Tab?,
        isRestoring: Bool, updateZeroQuery: Bool)
}

// We can't use a WeakList here because this is a protocol.
class WeakTabManagerDelegate {
    weak var value: TabManagerDelegate?

    init(value: TabManagerDelegate) {
        self.value = value
    }

    func get() -> TabManagerDelegate? {
        return value
    }
}

extension TabManager: TabEventHandler {
    func tab(_ tab: Tab, didLoadFavicon favicon: Favicon?, with: Data?) {
        // Write the tabs out again to make sure we preserve the favicon update.
        store.preserveTabs(tabs, selectedTab: selectedTab, for: scene)
    }

    func tabDidChangeContentBlocking(_ tab: Tab) {
        tab.reload()
    }
}

// TabManager must extend NSObjectProtocol in order to implement WKNavigationDelegate
class TabManager: NSObject {
    fileprivate var delegates = [WeakTabManagerDelegate]()
    fileprivate let tabEventHandlers: [TabEventHandler]
    public let store: TabManagerStore
    public var scene: UIScene
    let profile: Profile
    let incognitoModel: IncognitoModel

    let delaySelectingNewPopupTab: TimeInterval = 0.1

    static var all = WeakList<TabManager>()

    func addDelegate(_ delegate: TabManagerDelegate) {
        assert(Thread.isMainThread)
        delegates.append(WeakTabManagerDelegate(value: delegate))
    }

    func removeDelegate(_ delegate: TabManagerDelegate) {
        assert(Thread.isMainThread)
        for i in 0..<delegates.count {
            let del = delegates[i]
            if delegate === del.get() || del.get() == nil {
                delegates.remove(at: i)
                return
            }
        }
    }

    private(set) var tabs = [Tab]()
    private(set) var tabsUpdatedPublisher = PassthroughSubject<Void, Never>()

    var didRestoreAllTabs: Bool = false

    // Use `selectedTabPublisher` to observe changes to `selectedTab`.
    var selectedTab: Tab?
    var selectedTabPublisher = PassthroughSubject<Tab?, Never>()
    var selectedTabWillChangePublisher = PassthroughSubject<(Tab?, Tab?), Never>()

    fileprivate let navDelegate: TabManagerNavDelegate

    public static func makeWebViewConfig(isPrivate: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.phoneNumber]
        configuration.processPool = WKProcessPool()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !Defaults[.blockPopups]
        // We do this to go against the configuration of the <meta name="viewport">
        // tag to behave the same way as Safari :-(
        configuration.ignoresViewportScaleLimits = true
        if isPrivate {
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }
        configuration.setURLSchemeHandler(InternalSchemeHandler(), forURLScheme: InternalURL.scheme)

        return configuration
    }

    // A WKWebViewConfiguration used for normal tabs
    lazy var configuration: WKWebViewConfiguration = {
        return TabManager.makeWebViewConfig(isPrivate: false)
    }()

    // A WKWebViewConfiguration used for private mode tabs
    lazy fileprivate var privateConfiguration: WKWebViewConfiguration = {
        return TabManager.makeWebViewConfig(isPrivate: true)
    }()

    // enables undo of recently closed tabs
    /// supports closing/restoring a group of tabs or a single tab (alone in an array)
    var recentlyClosedTabs = [[SavedTab]]()

    // groups tabs closed together in a certain amount of time into one Toast
    let toastGroupTimerInterval: TimeInterval = 1.5
    var timerToTabsToast: Timer?
    var closedTabsToShowToastFor = [SavedTab]()

    var normalTabs: [Tab] {
        assert(Thread.isMainThread)
        return tabs.filter { !$0.isIncognito }
    }

    var incognitoTabs: [Tab] {
        assert(Thread.isMainThread)
        return tabs.filter { $0.isIncognito }
    }

    init(profile: Profile, scene: UIScene, incognitoModel: IncognitoModel) {
        assert(Thread.isMainThread)

        self.profile = profile
        self.navDelegate = TabManagerNavDelegate()
        self.tabEventHandlers = TabEventHandlers.create()
        self.store = TabManagerStore.shared
        self.scene = scene
        self.incognitoModel = incognitoModel
        super.init()

        Self.all.insert(self)

        register(self, forTabEvents: .didLoadFavicon, .didChangeContentBlocking)

        addNavigationDelegate(self)

        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsDidChange), name: UserDefaults.didChangeNotification,
            object: nil)
    }

    func addNavigationDelegate(_ delegate: WKNavigationDelegate) {
        assert(Thread.isMainThread)

        self.navDelegate.insert(delegate)
    }

    var count: Int {
        assert(Thread.isMainThread)

        return tabs.count
    }

    private var isIncognito: Bool {
        incognitoModel.isIncognito
    }

    subscript(index: Int) -> Tab? {
        assert(Thread.isMainThread)

        if index >= tabs.count {
            return nil
        }
        return tabs[index]
    }

    subscript(webView: WKWebView) -> Tab? {
        assert(Thread.isMainThread)

        for tab in tabs where tab.webView === webView {
            return tab
        }

        return nil
    }

    func getTabFor(_ url: URL) -> Tab? {
        assert(Thread.isMainThread)

        let options: [URL.EqualsOption] = [.normalizeHost, .ignoreFragment, .ignoreLastSlash]

        for tab in tabs.filter({ $0.isIncognito == self.isIncognito }) {
            if let webView = tab.webView {
                if let currentUrl = webView.url, url.equals(currentUrl, with: options) {
                    return tab
                }
            } else if let sessionUrl = tab.sessionData?.currentUrl {  // Match zombie tabs
                if url.equals(sessionUrl, with: options) {
                    return tab
                }

                if let internalUrl = InternalURL(sessionUrl), internalUrl.isSessionRestore,
                    let extractedUrlParam = internalUrl.extractedUrlParam,
                    url.equals(extractedUrlParam, with: options)
                {
                    return tab
                }
            }
        }

        return nil
    }

    func getTabCountForCurrentType() -> Int {
        let isPrivate = isIncognito

        if isPrivate {
            return incognitoTabs.count
        } else {
            return normalTabs.count
        }
    }

    // This function updates the _selectedIndex.
    // Note: it is safe to call this with `tab` and `previous` as the same tab, for use in the case where the index of the tab has changed (such as after deletion).
    func selectTab(_ tab: Tab?, previous: Tab? = nil, updateZeroQuery: Bool = true) {
        assert(Thread.isMainThread)
        let previous = previous ?? selectedTab

        // Make sure to wipe the private tabs if the user has the pref turned on
        if Defaults[.closePrivateTabs], !(tab?.isIncognito ?? false), incognitoTabs.count > 0 {
            removeAllIncognitoTabs()
        }

        selectedTab = tab

        incognitoModel.update(isIncognito: tab?.isIncognito ?? false)
        store.preserveTabs(tabs, selectedTab: selectedTab, for: scene)

        assert(tab === selectedTab, "Expected tab is selected")

        selectedTab?.createWebview()
        selectedTab?.lastExecutedTime = Date.nowMilliseconds()

        delegates.forEach {
            $0.get()?.tabManager(
                self, didSelectedTabChange: tab, previous: previous,
                isRestoring: store.isRestoringTabs,
                updateZeroQuery: updateZeroQuery)
        }

        if let tab = selectedTab {
            selectedTabPublisher.send(tab)
            selectedTabWillChangePublisher.send((previous, tab))
        }

        if let tab = previous {
            TabEvent.post(.didLoseFocus, for: tab)
        }

        if let tab = selectedTab {
            TabEvent.post(.didGainFocus, for: tab)
            tab.applyTheme()
        }

        if let tab = tab, tab.isIncognito, let url = tab.url, NeevaConstants.isAppHost(url.host),
            !url.path.starts(with: "/incognito")
        {
            tab.webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                if cookies.first(where: {
                    NeevaConstants.isAppHost($0.domain) && $0.name == "httpd~incognito"
                        && $0.isSecure
                }) != nil {
                    return
                }

                StartIncognitoMutation(url: url).perform { result in
                    guard
                        case .success(let data) = result,
                        let url = URL(string: data.startIncognito)
                    else { return }
                    let configuration = URLSessionConfiguration.ephemeral
                    makeURLSession(userAgent: UserAgent.getUserAgent(), configuration: .ephemeral)
                        .dataTask(with: url) { (data, response, error) in
                            print(configuration.httpCookieStorage?.cookies ?? [])
                        }
                }
            }
        }
    }

    func preserveTabs() {
        store.preserveTabs(tabs, selectedTab: selectedTab, for: scene)
    }

    //Called by other classes to signal that they are entering/exiting private mode
    //This is called by TabTrayVC when the private mode button is pressed and BEFORE we've switched to the new mode
    //we only want to remove all private tabs when leaving PBM and not when entering.
    func willSwitchTabMode(leavingPBM: Bool) {
        // Clear every time entering/exiting this mode.
        Tab.ChangeUserAgent.privateModeHostList = Set<String>()

        if Defaults[.closePrivateTabs] && leavingPBM {
            removeAllIncognitoTabs()
        }
    }

    func addPopupForParentTab(
        bvc: BrowserViewController, parentTab: Tab, configuration: WKWebViewConfiguration
    ) -> Tab {
        let popup = Tab(bvc: bvc, configuration: configuration, isPrivate: parentTab.isIncognito)
        configureTab(
            popup, request: nil, afterTab: parentTab, flushToDisk: true, zombie: false,
            isPopup: true, notify: true)

        // Wait momentarily before selecting the new tab, otherwise the parent tab
        // may be unable to set `window.location` on the popup immediately after
        // calling `window.open("")`.
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySelectingNewPopupTab) {
            self.selectTab(popup)
        }

        return popup
    }

    @discardableResult func addTab(
        _ request: URLRequest! = nil, configuration: WKWebViewConfiguration! = nil,
        afterTab: Tab? = nil, isPrivate: Bool = false,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil, notify: Bool = true
    ) -> Tab {
        return self.addTab(
            request, configuration: configuration, afterTab: afterTab, flushToDisk: true,
            zombie: false, isPrivate: isPrivate,
            query: query, suggestedQuery: suggestedQuery,
            visitType: visitType, notify: notify
        )
    }

    func addTabsForURLs(_ urls: [URL], zombie: Bool) {
        assert(Thread.isMainThread)

        if urls.isEmpty {
            return
        }

        var tab: Tab!
        for url in urls {
            tab = self.addTab(
                URLRequest(url: url), flushToDisk: false, zombie: zombie, notify: false)
        }

        // Select the most recent.
        selectTab(tab)

        // Okay now notify that we bulk-loaded so we can adjust counts and animate changes.
        tabsUpdatedPublisher.send()

        // Flush.
        storeChanges()
    }

    func addTab(
        _ request: URLRequest? = nil, webView: WKWebView? = nil,
        configuration: WKWebViewConfiguration? = nil, atIndex: Int? = nil, afterTab: Tab? = nil,
        flushToDisk: Bool, zombie: Bool, isPrivate: Bool = false,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil, notify: Bool = true
    ) -> Tab {
        assert(Thread.isMainThread)

        // Take the given configuration. Or if it was nil, take our default configuration for the current browsing mode.
        let configuration: WKWebViewConfiguration =
            configuration ?? (isPrivate ? privateConfiguration : self.configuration)

        let bvc = SceneDelegate.getBVC(with: scene)
        let tab = Tab(bvc: bvc, configuration: configuration, isPrivate: isPrivate)
        configureTab(
            tab, request: request, webView: webView, atIndex: atIndex, afterTab: afterTab,
            flushToDisk: flushToDisk, zombie: zombie,
            query: query, suggestedQuery: suggestedQuery,
            visitType: visitType,
            notify: notify)

        return tab
    }

    enum CreateOrSwitchToTabResult {
        case createdNewTab
        case switchedToExistingTab
    }

    @discardableResult func createOrSwitchToTab(
        for url: URL,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil
    )
        -> CreateOrSwitchToTabResult
    {
        if let existingTab = getTabFor(url) {
            select(existingTab)
            existingTab.browserViewController?
                .postLocationChangeNotificationForTab(existingTab, visitType: visitType)
            return .switchedToExistingTab
        } else {
            select(
                addTab(
                    URLRequest(url: url),
                    flushToDisk: true,
                    zombie: false,
                    isPrivate: isIncognito,
                    query: query,
                    suggestedQuery: suggestedQuery,
                    visitType: visitType
                )
            )
            return .createdNewTab
        }
    }

    @discardableResult func createOrSwitchToTabForSpace(for url: URL, spaceID: String)
        -> CreateOrSwitchToTabResult
    {
        if let tab = selectedTab {
            ScreenshotHelper(controller: SceneDelegate.getBVC(with: scene)).takeScreenshot(tab)
        }

        if let existingTab = getTabFor(url) {
            existingTab.parentSpaceID = spaceID
            existingTab.rootUUID = spaceID
            select(existingTab)
            return .switchedToExistingTab
        } else {
            let newTab = addTab(
                URLRequest(url: url), flushToDisk: true, zombie: false, isPrivate: isIncognito)
            newTab.parentSpaceID = spaceID
            newTab.rootUUID = spaceID
            select(newTab)
            return .createdNewTab
        }
    }

    func insertTab(_ tab: Tab, atIndex: Int? = nil, parent: Tab? = nil, notify: Bool) {
        if let atIndex = atIndex, atIndex <= tabs.count {
            tabs.insert(tab, at: atIndex)
        } else if parent == nil || parent?.isIncognito != tab.isIncognito {
            tabs.append(tab)
        } else if let parent = parent, var insertIndex = tabs.firstIndex(of: parent) {
            insertIndex += 1
            while insertIndex < tabs.count && tabs[insertIndex].isDescendentOf(parent) {
                insertIndex += 1
            }

            tab.parent = parent
            if FeatureFlag[.tabGroupsPinning] {
                tab.parent?.isPinned = (tab.parent?.parentUUID == nil)
            }
            tab.parentUUID = parent.tabUUID
            tab.rootUUID = parent.rootUUID
            tabs.insert(tab, at: insertIndex)
        }

        if notify {
            tabsUpdatedPublisher.send()
        }
    }

    func configureTab(
        _ tab: Tab, request: URLRequest?, webView: WKWebView? = nil, atIndex: Int? = nil,
        afterTab parent: Tab? = nil, flushToDisk: Bool, zombie: Bool, isPopup: Bool = false,
        query: String? = nil, suggestedQuery: String? = nil,
        visitType: VisitType? = nil, notify: Bool
    ) {
        assert(Thread.isMainThread)

        // If network is not available webView(_:didCommit:) is not going to be called
        // We should set request url in order to show url in url bar even no network
        tab.setURL(request?.url)

        insertTab(tab, atIndex: atIndex, parent: parent, notify: notify)

        if let webView = webView {
            tab.restore(webView)
        } else if !zombie {
            tab.createWebview()
        }

        tab.navigationDelegate = self.navDelegate
        if let query = query {
            tab.queryForNavigation.currentQuery = .init(typed: query, suggested: suggestedQuery)
        }

        if let request = request {
            if let nav = tab.loadRequest(request), let visitType = visitType {
                tab.browserViewController?.recordNavigationInTab(
                    tab, navigation: nav, visitType: visitType
                )
            }
        } else if !isPopup {
            let url = InternalURL.baseUrl / "about" / "home"
            tab.loadRequest(PrivilegedRequest(url: url) as URLRequest)
            tab.setURL(url)
        }

        if flushToDisk {
            storeChanges()
        }
    }

    // TODO(darin): Refactor these methods to set incognito mode. These should probably
    // move to `BrowserModel` and `TabManager` should just observe `IncognitoModel`.

    func setIncognitoMode(to isIncognito: Bool) {
        self.incognitoModel.update(isIncognito: isIncognito)
    }

    func toggleIncognitoMode(
        fromTabTray: Bool = true, clearSelectedTab: Bool = true, openLazyTab: Bool = true
    ) {
        let bvc = SceneDelegate.getBVC(with: scene)

        // set to nil while inconito changes
        if clearSelectedTab {
            selectedTab = nil
        }

        incognitoModel.toggle()

        if let mostRecentTab = mostRecentTab(inTabs: isIncognito ? incognitoTabs : normalTabs) {
            selectTab(mostRecentTab)
        } else if isIncognito && openLazyTab {  // no empty tab tray in incognito
            bvc.openLazyTab(openedFrom: fromTabTray ? .tabTray : .openTab(selectedTab))
        } else {
            let placeholderTab = Tab(bvc: bvc, configuration: configuration, isPrivate: isIncognito)

            // Creates a placeholder Tab to make sure incognito is switched in the Top Bar
            select(placeholderTab)
        }
    }

    func switchIncognitoMode(
        incognito: Bool, fromTabTray: Bool = true, clearSelectedTab: Bool = true,
        openLazyTab: Bool = true
    ) {
        if isIncognito != incognito {
            toggleIncognitoMode(
                fromTabTray: fromTabTray, clearSelectedTab: clearSelectedTab,
                openLazyTab: openLazyTab)
        }
    }

    func removeTabAndUpdateSelectedTab(_ tab: Tab, allowToast: Bool = false) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        addTabsToRecentlyClosed([tab], allowToast: allowToast)
        removeTab(tab, flushToDisk: true, notify: true)

        updateTabAfterRemovalOf(tab, deletedIndex: index)
    }

    private func updateTabAfterRemovalOf(_ tab: Tab, deletedIndex: Int) {
        let closedLastNormalTab = !tab.isIncognito && normalTabs.isEmpty
        let closedLastPrivateTab = tab.isIncognito && incognitoTabs.isEmpty
        let viableTabs: [Tab] = tab.isIncognito ? incognitoTabs : normalTabs
        let bvc = SceneDelegate.getBVC(with: scene)

        if closedLastNormalTab || closedLastPrivateTab {
            DispatchQueue.main.async {
                bvc.showTabTray()
            }
        } else if tab == selectedTab {
            if !selectParentTab(afterRemoving: tab) {
                if let rightOrLeftTab = viableTabs[safe: deletedIndex]
                    ?? viableTabs[safe: deletedIndex - 1]
                {
                    selectTab(rightOrLeftTab, previous: tab)
                } else {
                    selectTab(mostRecentTab(inTabs: viableTabs) ?? viableTabs.last, previous: tab)
                }
            }
        }
    }

    /// - Parameter notify: if set to true, will call the delegate after the tab
    ///   is removed.
    fileprivate func removeTab(_ tab: Tab, flushToDisk: Bool, notify: Bool) {
        assert(Thread.isMainThread)

        guard let removalIndex = tabs.firstIndex(where: { $0 === tab }) else {
            Sentry.shared.sendWithStacktrace(
                message: "Could not find index of tab to remove", tag: .tabManager,
                severity: .fatal, description: "Tab count: \(count)")
            return
        }

        let prevCount = count
        tabs.remove(at: removalIndex)
        assert(count == prevCount - 1, "Make sure the tab count was actually removed")

        if tab.isIncognito && incognitoTabs.count < 1 {
            privateConfiguration = TabManager.makeWebViewConfig(isPrivate: true)
        }

        tab.close()

        if notify {
            TabEvent.post(.didClose, for: tab)
            tabsUpdatedPublisher.send()
        }

        if flushToDisk {
            storeChanges()
        }
    }

    // Select the most recently visited tab, IFF it is also the parent tab of the closed tab.
    func selectParentTab(afterRemoving tab: Tab) -> Bool {
        let viableTabs = (tab.isIncognito ? incognitoTabs : normalTabs).filter { $0 != tab }
        guard let parentTab = tab.parent, parentTab != tab, !viableTabs.isEmpty,
            viableTabs.contains(parentTab)
        else { return false }

        let parentTabIsMostRecentUsed = mostRecentTab(inTabs: viableTabs) == parentTab

        if parentTabIsMostRecentUsed, parentTab.lastExecutedTime != nil {
            selectTab(parentTab, previous: tab)
            return true
        }
        return false
    }

    func removeAllTabs() {
        removeTabs(tabs, showToast: false)
    }

    private func removeAllIncognitoTabs() {
        removeTabs(incognitoTabs, updatingSelectedTab: true)
        privateConfiguration = TabManager.makeWebViewConfig(isPrivate: true)
    }

    func removeTabs(
        _ tabsToBeRemoved: [Tab], showToast: Bool = true
    ) {
        guard tabsToBeRemoved.count > 0 else {
            return
        }

        addTabsToRecentlyClosed(tabsToBeRemoved, allowToast: showToast)

        let lastTab = tabsToBeRemoved[tabsToBeRemoved.count - 1]
        let lastTabIndex = tabs.firstIndex(of: lastTab)
        let tabsToKeep = self.tabs.filter { !tabsToBeRemoved.contains($0) }
        self.tabs = tabsToKeep

        if let lastTabIndex = lastTabIndex {
            updateTabAfterRemovalOf(lastTab, deletedIndex: lastTabIndex)
        }

        storeChanges()

        tabsUpdatedPublisher.send()

        // TODO(darin): Don't we need to call Tab.close() on each of the removed tabs, and
        // don't we need to generate a .didClose TabEvent?
    }

    func addTabsToRecentlyClosed(_ tabs: [Tab], allowToast: Bool) {
        // Avoid remembering incognito tabs.
        let tabs = tabs.filter { !$0.isIncognito }
        if tabs.isEmpty {
            return
        }

        let savedTabs = tabs.map {
            SavedTab(
                tab: $0, isSelected: selectedTab === $0, tabIndex: self.tabs.firstIndex(of: $0))
        }
        recentlyClosedTabs.insert(savedTabs, at: 0)

        if allowToast {
            closedTabsToShowToastFor.append(contentsOf: savedTabs)

            timerToTabsToast?.invalidate()
            timerToTabsToast = Timer.scheduledTimer(
                withTimeInterval: toastGroupTimerInterval, repeats: false,
                block: { _ in
                    ToastDefaults().showToastForClosedTabs(
                        self.closedTabsToShowToastFor, tabManager: self)
                    self.closedTabsToShowToastFor.removeAll()
                })
        }
    }

    func restoreSavedTabs(
        _ savedTabs: [SavedTab], isPrivate: Bool = false, shouldSelectTab: Bool = true
    ) -> Tab? {
        // makes sure at least one tab is selected
        // if no tab selected, select the last one (most recently closed)
        var selectedSavedTab: Tab?

        for index in 0..<savedTabs.count {
            let savedTab = savedTabs[index]
            let urlRequest: URLRequest? = savedTab.url != nil ? URLRequest(url: savedTab.url!) : nil

            var tab: Tab!
            if let tabIndex = savedTab.tabIndex {
                tab = addTab(
                    urlRequest, atIndex: tabIndex, flushToDisk: false, zombie: false,
                    isPrivate: isPrivate, notify: false)
            } else {
                tab = addTab(
                    urlRequest, afterTab: getTabForUUID(uuid: savedTab.parentUUID ?? ""),
                    flushToDisk: false, zombie: false, isPrivate: isPrivate, notify: false)
            }

            tab = savedTab.configureSavedTabUsing(tab, imageStore: store.imageStore)
            tab.restore(tab.webView!)

            if savedTab.isSelected {
                selectedSavedTab = tab
            } else if index == savedTabs.count - 1 && selectedSavedTab == nil {
                selectedSavedTab = tab
            }
        }

        tabsUpdatedPublisher.send()

        // Prevents a sticky tab tray
        SceneDelegate.getBVC(with: scene).browserModel.cardTransitionModel.update(to: .hidden)

        if let selectedSavedTab = selectedSavedTab, shouldSelectTab {
            self.selectTab(selectedSavedTab)
        }

        // remove restored tabs from recently closed
        if let index = recentlyClosedTabs.firstIndex(of: savedTabs) {
            recentlyClosedTabs.remove(at: index)
        }

        closedTabsToShowToastFor.removeAll { savedTabs.contains($0) }

        return selectedSavedTab
    }

    func restoreAllClosedTabs() {
        _ = restoreSavedTabs(Array(recentlyClosedTabs.joined()))
    }

    // TODO(darin): De-dupe this with the other variant of `removeTabs` above.
    func removeTabs(_ tabs: [Tab], updatingSelectedTab: Bool) {
        guard tabs.count > 0 else {
            return
        }

        var tabsExcludingLast = tabs

        if updatingSelectedTab {
            tabsExcludingLast.removeLast()
        }

        let filteredTabs = self.tabs.filter { !tabs.contains($0) }
        self.tabs = filteredTabs

        // Update the selected tab after removing the last tab
        if updatingSelectedTab {
            removeTabAndUpdateSelectedTab(tabs[tabs.count - 1])
        }

        storeChanges()

        tabsUpdatedPublisher.send()

        // TODO(darin): Don't we need to call Tab.close() on each of the removed tabs, and
        // don't we need to generate a .didClose TabEvent?
    }

    func getRecentlyClosedTabForURL(_ url: URL) -> SavedTab? {
        assert(Thread.isMainThread)
        return recentlyClosedTabs.joined().filter({ $0.url == url }).first
    }

    func getTabForUUID(uuid: String) -> Tab? {
        assert(Thread.isMainThread)
        let filterdTabs = tabs.filter { tab -> Bool in
            tab.tabUUID == uuid
        }
        return filterdTabs.first
    }

    @objc func prefsDidChange() {
        DispatchQueue.main.async {
            let allowPopups = !Defaults[.blockPopups]
            // Each tab may have its own configuration, so we should tell each of them in turn.
            for tab in self.tabs {
                tab.webView?.configuration.preferences.javaScriptCanOpenWindowsAutomatically =
                    allowPopups
            }
            // The default tab configurations also need to change.
            self.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
            self.privateConfiguration.preferences.javaScriptCanOpenWindowsAutomatically =
                allowPopups
        }
    }

    func resetProcessPool() {
        assert(Thread.isMainThread)
        configuration.processPool = WKProcessPool()
    }
}

extension TabManager {
    private func saveTabs(toProfile profile: Profile, _ tabs: [Tab]) {
        // It is possible that not all tabs have loaded yet, so we filter out tabs with a nil URL.
        let storedTabs: [RemoteTab] = tabs.compactMap(Tab.toRemoteTab)

        // Don't insert into the DB immediately. We tend to contend with more important
        // work like querying for top sites.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            profile.storeTabs(storedTabs)
        }
    }

    private func storeChanges() {
        saveTabs(toProfile: profile, normalTabs)
        store.preserveTabs(
            tabs, selectedTab: selectedTab, for: scene)
    }

    private func hasTabsToRestoreAtStartup() -> Bool {
        return store.getStartupTabs(for: scene).count > 0
    }

    /// - Returns: Returns a bool of whether there were tabs to restore
    func restoreTabs(_ forced: Bool = false) -> Bool {
        log.info("Restoring tabs")

        guard forced || count == 0, !AppConstants.IsRunningTest,
            !DebugSettingsBundleOptions.skipSessionRestore, hasTabsToRestoreAtStartup()
        else {
            log.info("Skipping tab restore")
            didRestoreAllTabs = true
            tabsUpdatedPublisher.send()
            return false
        }

        var tabToSelect = store.restoreStartupTabs(
            for: scene, clearPrivateTabs: Defaults[.closePrivateTabs], tabManager: self)
        if Defaults[.lastSessionPrivate], !(tabToSelect?.isIncognito ?? false) {
            tabToSelect = addTab(isPrivate: true, notify: false)
        }

        selectTab(tabToSelect)

        tabsUpdatedPublisher.send()
        return true
    }
}

extension TabManager: WKNavigationDelegate {

    // Note the main frame JSContext (i.e. document, window) is not available yet.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Save stats for the page we are leaving.
        if let tab = self[webView], let blocker = tab.contentBlocker, let url = tab.url {
            blocker.pageStatsCache[url] = blocker.stats
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Clear stats for the page we are newly generating.
        if navigationResponse.isForMainFrame, let tab = self[webView],
            let blocker = tab.contentBlocker, let url = navigationResponse.response.url
        {
            blocker.pageStatsCache[url] = nil
        }
        decisionHandler(.allow)
    }

    // The main frame JSContext is available, and DOM parsing has begun.
    // Do not excute JS at this point that requires running prior to DOM parsing.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = self[webView] else { return }

        tab.hasContentProcess = true

        if let url = webView.url, let blocker = tab.contentBlocker {
            // Initialize to the cached stats for this page. If the page is being fetched
            // from WebKit's page cache, then this will pick up stats from when that page
            // was previously loaded. If not, then the cached value will be empty.
            blocker.stats = blocker.pageStatsCache[url] ?? TPPageStats()
            if !blocker.isEnabled {
                webView.evaluateJavascriptInDefaultContentWorld(
                    "window.__firefox__.TrackingProtectionStats.setEnabled(false, \(UserScriptManager.appIdToken))"
                )
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // tab restore uses internal pages, so don't call storeChanges unnecessarily on startup
        if let url = webView.url {
            if let internalUrl = InternalURL(url), internalUrl.isSessionRestore {
                return
            }

            storeChanges()
        }
    }

    /// Called when the WKWebView's content process has gone away. If this happens for the currently selected tab
    /// then we immediately reload it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tab = self[webView] else { return }

        tab.hasContentProcess = false

        if tab == selectedTab {
            tab.consecutiveCrashes += 1

            // Only automatically attempt to reload the crashed
            // tab three times before giving up.
            if tab.consecutiveCrashes < 3 {
                webView.reload()
            } else {
                tab.consecutiveCrashes = 0
            }
        }
    }
}

// WKNavigationDelegates must implement NSObjectProtocol
class TabManagerNavDelegate: NSObject, WKNavigationDelegate {
    fileprivate var delegates = WeakList<WKNavigationDelegate>()

    func insert(_ delegate: WKNavigationDelegate) {
        delegates.insert(delegate)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didCommit: navigation)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)"), error: \(error)")

        for delegate in delegates {
            delegate.webView?(webView, didFail: navigation, withError: error)
        }
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)"), error: \(error)")

        for delegate in delegates {
            delegate.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didFinish: navigation)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webViewWebContentProcessDidTerminate?(webView)
        }
    }

    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        let authenticatingDelegates = delegates.filter { wv in
            return wv.responds(to: #selector(webView(_:didReceive:completionHandler:)))
        }

        guard let firstAuthenticatingDelegate = authenticatingDelegates.first else {
            return completionHandler(.performDefaultHandling, nil)
        }

        firstAuthenticatingDelegate.webView?(webView, didReceive: challenge) {
            (disposition, credential) in
            completionHandler(disposition, credential)
        }
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didReceiveServerRedirectForProvisionalNavigation: navigation)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.network.info("webView.url: \(webView.url ?? "(nil)")")

        for delegate in delegates {
            delegate.webView?(webView, didStartProvisionalNavigation: navigation)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        Logger.network.info(
            "webView.url: \(webView.url?.absoluteString ?? "(nil)"), request.url: \(navigationAction.request.url?.absoluteString ?? "(nil)"), isMainFrame: \(navigationAction.targetFrame?.isMainFrame.description ?? "(nil)")"
        )

        var res = WKNavigationActionPolicy.allow
        for delegate in delegates {
            delegate.webView?(
                webView, decidePolicyFor: navigationAction,
                decisionHandler: { policy in
                    if policy == .cancel {
                        res = policy
                    }
                })
        }
        decisionHandler(res)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        Logger.network.info(
            "webView.url: \(webView.url ?? "(nil)"), response.url: \(navigationResponse.response.url ?? "(nil)"), isMainFrame: \(navigationResponse.isForMainFrame)"
        )

        var res = WKNavigationResponsePolicy.allow
        for delegate in delegates {
            delegate.webView?(
                webView, decidePolicyFor: navigationResponse,
                decisionHandler: { policy in
                    if policy == .cancel {
                        res = policy
                    }
                })
        }

        decisionHandler(res)
    }
}

// Helper functions for test cases
extension TabManager {
    convenience init(profile: Profile, imageStore: DiskImageStore?) {
        assert(Thread.isMainThread)

        let scene = SceneDelegate.getCurrentScene(for: nil)
        let incognitoModel = IncognitoModel(isIncognito: false)
        self.init(profile: profile, scene: scene, incognitoModel: incognitoModel)
    }

    func testTabCountOnDisk() -> Int {
        assert(AppConstants.IsRunningTest)
        return store.testTabCountOnDisk(sceneId: SceneDelegate.getCurrentSceneId(for: nil))
    }

    func testCountRestoredTabs() -> Int {
        assert(AppConstants.IsRunningTest)
        return store.getStartupTabs(for: SceneDelegate.getCurrentScene(for: nil)).count
    }

    func testClearArchive() {
        assert(AppConstants.IsRunningTest)
        store.clearArchive(for: SceneDelegate.getCurrentScene(for: nil))
    }
}

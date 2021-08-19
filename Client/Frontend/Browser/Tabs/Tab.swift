/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Combine
import Foundation
import Shared
import Storage
import SwiftyJSON
import WebKit
import XCGLogger

private var debugTabCount = 0

func mostRecentTab(inTabs tabs: [Tab]) -> Tab? {
    var recent = tabs.first
    tabs.forEach { tab in
        if let time = tab.lastExecutedTime, time > (recent?.lastExecutedTime ?? 0) {
            recent = tab
        }
    }
    return recent
}

protocol TabContentScript {
    static func name() -> String
    func scriptMessageHandlerName() -> String?
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceiveScriptMessage message: WKScriptMessage)
}

@objc
protocol TabDelegate {
    func tab(_ tab: Tab, didSelectFindInPageForSelection selection: String)
    func tab(_ tab: Tab, didSelectSearchWithNeevaForSelection selection: String)
    @objc optional func tab(_ tab: Tab, didCreateWebView webView: WKWebView)
}

class Tab: NSObject, ObservableObject {
    let isIncognito: Bool

    // PageMetadata is derived from the page content itself, and as such lags behind the
    // rest of the tab.
    var pageMetadata: PageMetadata?

    var consecutiveCrashes: UInt = 0

    // Setting defualt page as topsites
    var tabUUID: String = UUID().uuidString

    // To check if current URL is the starting page i.e. either blank page or internal page like topsites
    var isURLStartingPage: Bool {
        guard url != nil else {
            return true
        }
        if url!.absoluteString.hasPrefix("internal://") {
            return true
        }
        return false
    }

    var canonicalURL: URL? {
        if let siteURL = pageMetadata?.siteURL {
            // If the canonical URL from the page metadata doesn't contain the
            // "#" fragment, check if the tab's URL has a fragment and if so,
            // append it to the canonical URL.
            if siteURL.fragment == nil,
                let fragment = self.url?.fragment,
                let siteURLWithFragment = URL(string: "\(siteURL.absoluteString)#\(fragment)")
            {
                return siteURLWithFragment
            }

            return siteURL
        }
        return self.url
    }

    var userActivity: NSUserActivity?

    private(set) var webView: WKWebView?
    var tabDelegate: TabDelegate?
    /// This set is cleared out when the tab is closed, ensuring that any subscriptions are invalidated.
    var webViewSubscriptions: Set<AnyCancellable> = []
    private var subscriptions: Set<AnyCancellable> = []

    @Published var favicons: [Favicon] = []
    var lastExecutedTime: Timestamp?
    var sessionData: SessionData?
    fileprivate var lastRequest: URLRequest?
    var restoring: Bool = false
    var pendingScreenshot = false

    // MARK: Properties mirrored from webView
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var title: String?
    /// For security reasons, the URL may differ from the web view’s URL.
    @Published private(set) var url: URL?

    func setURL(_ newValue: URL?) {
        if let internalUrl = InternalURL(newValue), internalUrl.isAuthorized {
            url = internalUrl.stripAuthorization
        } else {
            url = newValue
        }
    }

    var backList: [WKBackForwardListItem]? { webView?.backForwardList.backList }
    var forwardList: [WKBackForwardListItem]? { webView?.backForwardList.forwardList }

    var isEditing: Bool = false

    // When viewing a non-HTML content type in the webview (like a PDF document), this var will
    // be non-nil and hold a reference to a tempfile containing the downloaded content so it can
    // be shared to external applications.
    var temporaryDocument: TemporaryDocument?
    // During navigation, the instance is held in a provisional state here, and only promoted to
    // the above var when navigation commits.
    var provisionalTemporaryDocument: TemporaryDocument?

    var contentBlocker: NeevaTabContentBlocker?

    /// The last title shown by this tab. Used by the tab tray to show titles for zombie tabs.
    var lastTitle: String?

    /// Whether or not the desktop site was requested with the last request, reload or navigation.
    var changedUserAgent: Bool = false {
        didSet {
            if changedUserAgent != oldValue {
                TabEvent.post(.didToggleDesktopMode, for: self)
            }
        }
    }

    var readerModeAvailableOrActive: Bool {
        if let readerMode = self.getContentScript(name: "ReaderMode") as? ReaderMode {
            return readerMode.state != .unavailable
        }
        return false
    }

    fileprivate(set) var screenshot: UIImage?
    var screenshotUUID: UUID?

    // If this tab has been opened from another, its parent will point to the tab from which it was opened
    weak var parent: Tab?
    var parentUUID: String? = nil

    var rootUUID: String = UUID().uuidString

    fileprivate var contentScriptManager = TabContentScriptManager()

    fileprivate let configuration: WKWebViewConfiguration

    /// Any time a tab tries to make requests to display a Javascript Alert and we are not the active
    /// tab instance, queue it for later until we become foregrounded.
    fileprivate var alertQueue = [JSAlertInfo]()

    weak var browserViewController: BrowserViewController?

    init(bvc: BrowserViewController, configuration: WKWebViewConfiguration, isPrivate: Bool = false)
    {
        self.configuration = configuration
        self.browserViewController = bvc
        self.isIncognito = isPrivate
        super.init()

        debugTabCount += 1

        $favicons
            // grab the display favicon whenever the set of favicons change
            .map { [unowned self] _ in displayFavicon?.url }
            .removeDuplicates()
            // filter out nil URLs and URLs with invalid baseDomains,
            // and grab the baseDomain as a cache key
            .compactMap { url in url?.baseDomain.map { domain in (url, domain) } }
            // tell the favicon fetcher to cache the appropriate favicon
            .sink(receiveValue: FaviconFetcher.downloadFaviconAndCache(imageURL:imageKey:))
            .store(in: &subscriptions)
    }

    class func toRemoteTab(_ tab: Tab) -> RemoteTab? {
        if tab.isIncognito {
            return nil
        }

        if let displayURL = tab.url?.displayURL, RemoteTab.shouldIncludeURL(displayURL) {
            let history = Array(tab.historyList.filter(RemoteTab.shouldIncludeURL).reversed())
            return RemoteTab(
                clientGUID: nil,
                URL: displayURL,
                title: tab.displayTitle,
                history: history,
                lastUsed: Date.nowMilliseconds(),
                icon: nil)
        } else if let sessionData = tab.sessionData, !sessionData.urls.isEmpty {
            let history = Array(sessionData.urls.filter(RemoteTab.shouldIncludeURL).reversed())
            if let displayURL = history.first {
                return RemoteTab(
                    clientGUID: nil,
                    URL: displayURL,
                    title: tab.displayTitle,
                    history: history,
                    lastUsed: sessionData.lastUsedTime,
                    icon: nil)
            }
        }

        return nil
    }

    weak var navigationDelegate: WKNavigationDelegate? {
        didSet {
            if let webView = webView {
                webView.navigationDelegate = navigationDelegate
            }
        }
    }

    func createWebview() {
        if webView == nil {
            configuration.userContentController = WKUserContentController()
            configuration.allowsInlineMediaPlayback = true
            let webView = TabWebView(frame: .zero, configuration: configuration)
            webView.delegate = self

            webView.accessibilityLabel = .WebViewAccessibilityLabel
            webView.allowsBackForwardNavigationGestures = true

            if UIDevice.current.userInterfaceIdiom == .phone {
                let rc = UIRefreshControl(
                    frame: .zero,
                    primaryAction: UIAction { [weak self] _ in
                        self?.reload()
                        // Dismiss refresh control now as the regular progress bar will soon appear.
                        self?.webView?.scrollView.refreshControl?.endRefreshing()
                    })
                webView.scrollView.refreshControl = rc
                webView.scrollView.bringSubviewToFront(rc)
            }

            webView.allowsLinkPreview = true

            // Turning off masking allows the web content to flow outside of the scrollView's frame
            // which allows the content appear beneath the toolbars in the BrowserViewController
            webView.scrollView.layer.masksToBounds = false
            webView.navigationDelegate = navigationDelegate

            restore(webView)

            self.webView = webView

            send(webView: \.isLoading, to: \.isLoading)
            send(webView: \.canGoBack, to: \.canGoBack)
            send(webView: \.canGoForward, to: \.canGoForward)
            send(webView: \.title, to: \.title)

            $isLoading
                .combineLatest(webView.publisher(for: \.estimatedProgress, options: .new))
                .sink { isLoading, progress in
                    // Unfortunately WebKit can report partial progress when isLoading is false! That can
                    // happen when a load is cancelled. Avoid reporting partial progress here, but take
                    // care to let the case of progress complete (value of 1) through.
                    self.estimatedProgress = (isLoading || progress == 1) ? progress : 0
                }
                .store(in: &webViewSubscriptions)

            UserScriptManager.shared.injectUserScriptsIntoTab(self)
            tabDelegate?.tab?(self, didCreateWebView: webView)
        }
    }

    /// Helper function to observe changes to a given key path on the web view and assign
    /// them to a property on `self`. Stores the subscription in `webViewSubscriptions`
    /// for future disposal in `close()`
    private func send<T>(
        webView keyPath: KeyPath<WKWebView, T>,
        to localKeyPath: ReferenceWritableKeyPath<Tab, T>
    ) {
        webView?.publisher(for: keyPath, options: [.initial, .new])
            .assign(to: localKeyPath, on: self)
            .store(in: &webViewSubscriptions)
    }

    func restore(_ webView: WKWebView) {
        // Pulls restored session data from a previous SavedTab to load into the Tab. If it's nil, a session restore
        // has already been triggered via custom URL, so we use the last request to trigger it again; otherwise,
        // we extract the information needed to restore the tabs and create a NSURLRequest with the custom session restore URL
        // to trigger the session restore via custom handlers
        if let sessionData = self.sessionData {
            restoring = true

            var urls = [String]()
            for url in sessionData.urls {
                urls.append(url.absoluteString)
            }

            let currentPage = sessionData.currentPage
            self.sessionData = nil
            var jsonDict = [String: AnyObject]()
            jsonDict["history"] = urls as AnyObject?
            jsonDict["currentPage"] = currentPage as AnyObject?
            guard
                let json = JSON(jsonDict).stringify()?.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed)
            else {
                return
            }

            if let restoreURL = URL(
                string: "\(InternalURL.baseUrl)/\(SessionRestoreHandler.path)?history=\(json)")
            {
                let request = PrivilegedRequest(url: restoreURL) as URLRequest
                webView.load(request)
                lastRequest = request
            }
        } else if let request = lastRequest {
            webView.load(request)
        } else {
            print(
                "creating webview with no lastRequest and no session data: \(self.url?.description ?? "nil")"
            )
        }
    }

    deinit {
        debugTabCount -= 1

        #if DEBUG___DISABLED
            guard let appDelegate = UIApplication.shared.bvc as? AppDelegate else { return }
            func checkTabCount(failures: Int) {
                // Need delay for pool to drain.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if appDelegate.tabManager.tabs.count == debugTabCount {
                        return
                    }

                    // If this assert has false positives, remove it and just log an error.
                    assert(failures < 3, "Tab init/deinit imbalance, possible memory leak.")
                    checkTabCount(failures: failures + 1)
                }
            }
            checkTabCount(failures: 0)
        #endif
    }

    func close() {
        contentScriptManager.uninstall(tab: self)
        cancelQueuedAlerts()
        webViewSubscriptions = []
        /// This check causes crashes in ClientTests. It looks like there are no strong references to
        /// the web view, so I’m chalking it up to Swift being lazy.
        //DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(10)) { [weak webView] in
        //    if let webView = webView {
        //        assertionFailure("web view with URL \(webView.url ?? "(nil)") \(webView) was not deallocated")
        //    }
        //}
        webView = nil
    }

    var historyList: [URL] {
        func listToUrl(_ item: WKBackForwardListItem) -> URL { return item.url }
        var tabs = self.backList?.map(listToUrl) ?? [URL]()
        if let url = url {
            tabs.append(url)
        }
        return tabs
    }

    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }

        // When picking a display title. Tabs with sessionData are pending a restore so show their old title.
        // To prevent flickering of the display title. If a tab is restoring make sure to use its lastTitle.
        if let url = self.url, InternalURL(url)?.isZeroQueryURL ?? false, sessionData == nil,
            !restoring
        {
            return Strings.AppMenuOpenHomePageTitleString
        }

        //lets double check the sessionData in case this is a non-restored new tab
        if let firstURL = sessionData?.urls.first, sessionData?.urls.count == 1,
            InternalURL(firstURL)?.isZeroQueryURL ?? false
        {
            return Strings.AppMenuOpenHomePageTitleString
        }

        if let url = self.url, !InternalURL.isValid(url: url),
            let shownUrl = url.displayURL?.absoluteString
        {
            return shownUrl
        }

        guard let lastTitle = lastTitle, !lastTitle.isEmpty else {
            return self.url?.displayURL?.absoluteString ?? ""
        }

        return lastTitle
    }

    var displayFavicon: Favicon? { favicons.max { $0.width! < $1.width! } }

    func goBack() {
        _ = webView?.goBack()
    }

    func goForward() {
        _ = webView?.goForward()
    }

    func goToBackForwardListItem(_ item: WKBackForwardListItem) {
        _ = webView?.go(to: item)
    }

    @discardableResult func loadRequest(_ request: URLRequest) -> WKNavigation? {
        if let webView = webView {
            // Convert about:reader?url=http://example.com URLs to local ReaderMode URLs
            if let url = request.url, let syncedReaderModeURL = url.decodeReaderModeURL,
                let localReaderModeURL = syncedReaderModeURL.encodeReaderModeURL(
                    WebServer.sharedInstance.baseReaderModeURL())
            {
                let readerModeRequest = PrivilegedRequest(url: localReaderModeURL) as URLRequest
                lastRequest = readerModeRequest
                return webView.load(readerModeRequest)
            }
            lastRequest = request
            if let url = request.url, url.isFileURL, request.isPrivileged {
                return webView.loadFileURL(url, allowingReadAccessTo: url)
            }

            return webView.load(request)
        }
        return nil
    }

    func stop() {
        webView?.stopLoading()
    }

    func reload() {
        // If the current page is an error page, and the reload button is tapped, load the original URL
        if let url = webView?.url, let internalUrl = InternalURL(url),
            let page = internalUrl.originalURLFromErrorPage
        {
            webView?.replaceLocation(with: page)
            return
        }

        if let _ = webView?.reloadFromOrigin() {
            print("reloaded zombified tab from origin")
            return
        }

        if let webView = self.webView {
            print("restoring webView from scratch")
            restore(webView)
        }
    }

    func addContentScript(_ helper: TabContentScript, name: String) {
        contentScriptManager.addContentScript(helper, name: name, forTab: self)
    }

    func getContentScript(name: String) -> TabContentScript? {
        return contentScriptManager.getContentScript(name)
    }

    func hideContent(_ animated: Bool = false) {
        webView?.isUserInteractionEnabled = false
        if animated {
            UIView.animate(
                withDuration: 0.25,
                animations: { () -> Void in
                    self.webView?.alpha = 0.0
                })
        } else {
            webView?.alpha = 0.0
        }
    }

    func showContent(_ animated: Bool = false) {
        webView?.isUserInteractionEnabled = true
        if animated {
            UIView.animate(
                withDuration: 0.25,
                animations: { () -> Void in
                    self.webView?.alpha = 1.0
                })
        } else {
            webView?.alpha = 1.0
        }
    }

    func setScreenshot(_ screenshot: UIImage?, revUUID: Bool = true) {
        self.screenshot = screenshot
        if revUUID {
            self.screenshotUUID = UUID()
        }
    }

    func toggleChangeUserAgent() {
        changedUserAgent = !changedUserAgent
        reload()
    }

    func queueJavascriptAlertPrompt(_ alert: JSAlertInfo) {
        alertQueue.append(alert)
    }

    func dequeueJavascriptAlertPrompt() -> JSAlertInfo? {
        guard !alertQueue.isEmpty else {
            return nil
        }
        return alertQueue.removeFirst()
    }

    func cancelQueuedAlerts() {
        alertQueue.forEach { alert in
            alert.cancel()
        }
    }

    func isDescendentOf(_ ancestor: Tab) -> Bool {
        return sequence(first: parent) { $0?.parent }.contains { $0 == ancestor }
    }

    func applyTheme() {
        UITextField.appearance().keyboardAppearance = isIncognito ? .dark : .default
    }
}

extension Tab: TabWebViewDelegate {
    fileprivate func tabWebView(
        _ tabWebView: TabWebView, didSelectFindInPageForSelection selection: String
    ) {
        tabDelegate?.tab(self, didSelectFindInPageForSelection: selection)
    }
    fileprivate func tabWebViewSearchWithNeeva(
        _ tabWebViewSearchWithNeeva: TabWebView,
        didSelectSearchWithNeevaForSelection selection: String
    ) {
        tabDelegate?.tab(self, didSelectSearchWithNeevaForSelection: selection)
    }
}

extension Tab: ContentBlockerTab {
    func currentURL() -> URL? {
        return url
    }

    func currentWebView() -> WKWebView? {
        return webView
    }
}

private class TabContentScriptManager: NSObject, WKScriptMessageHandler {
    private var helpers = [String: TabContentScript]()

    // Without calling this, the TabContentScriptManager will leak.
    func uninstall(tab: Tab) {
        helpers.forEach { helper in
            if let name = helper.value.scriptMessageHandlerName() {
                tab.webView?.configuration.userContentController.removeScriptMessageHandler(
                    forName: name)
            }
        }
    }

    @objc func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        for helper in helpers.values {
            if let scriptMessageHandlerName = helper.scriptMessageHandlerName(),
                scriptMessageHandlerName == message.name
            {
                helper.userContentController(
                    userContentController, didReceiveScriptMessage: message)
                return
            }
        }
    }

    func addContentScript(_ helper: TabContentScript, name: String, forTab tab: Tab) {
        if helpers[name] != nil {
            assertionFailure("Duplicate helper added: \(name)")
        }

        helpers[name] = helper

        // If this helper handles script messages, then get the handler name and register it. The Browser
        // receives all messages and then dispatches them to the right TabHelper.
        if let scriptMessageHandlerName = helper.scriptMessageHandlerName() {
            tab.webView?.configuration.userContentController.addInDefaultContentWorld(
                scriptMessageHandler: self, name: scriptMessageHandlerName)
        }
    }

    func getContentScript(_ name: String) -> TabContentScript? {
        return helpers[name]
    }
}

private protocol TabWebViewDelegate: AnyObject {
    func tabWebView(_ tabWebView: TabWebView, didSelectFindInPageForSelection selection: String)
    func tabWebViewSearchWithNeeva(
        _ tabWebViewSearchWithNeeva: TabWebView,
        didSelectSearchWithNeevaForSelection selection: String)
}

class TabWebView: WKWebView, MenuHelperInterface {
    fileprivate weak var delegate: TabWebViewDelegate?

    // Updates the `background-color` of the webview to match
    // the theme if the webview is showing "about:blank" (nil).
    func applyTheme() {
        if url == nil {
            let backgroundColor = UIColor.DefaultBackground.hexString
            evaluateJavascriptInDefaultContentWorld(
                "document.documentElement.style.backgroundColor = '\(backgroundColor)';")
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return super.canPerformAction(action, withSender: sender)
            || action == MenuHelper.SelectorFindInPage
    }

    @objc func menuHelperFindInPage() {
        evaluateJavascriptInDefaultContentWorld("getSelection().toString()") { result, _ in
            let selection = result as? String ?? ""
            self.delegate?.tabWebView(self, didSelectFindInPageForSelection: selection)
        }
    }

    @objc func menuHelperSearchWithNeeva() {
        evaluateJavascriptInDefaultContentWorld("getSelection().toString()") { result, _ in
            let selection = result as? String ?? ""
            self.delegate?.tabWebViewSearchWithNeeva(
                self, didSelectSearchWithNeevaForSelection: selection)
        }
    }

    internal override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The find-in-page selection menu only appears if the webview is the first responder.
        becomeFirstResponder()

        return super.hitTest(point, with: event)
    }

    /// Override evaluateJavascript - should not be called directly on TabWebViews any longer
    // We should only be calling evaluateJavascriptInDefaultContentWorld in the future
    @available(
        *, unavailable,
        message:
            "Do not call evaluateJavaScript directly on TabWebViews, should only be called on super class"
    )
    override func evaluateJavaScript(
        _ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil
    ) {
        super.evaluateJavaScript(javaScriptString, completionHandler: completionHandler)
    }
}
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import CoreServices
import CoreSpotlight
import Foundation
import Shared
import Storage
import SwiftUI
import WebKit

private let searchableIndex = CSSearchableIndex(name: "neeva")

class UserActivityHandler {
    static let browsingActivityType: String = "co.neeva.app.ios.browser.browsing"

    init() {
        register(
            self, forTabEvents: .didClose, .didLoseFocus, .didGainFocus, .didChangeURL,
            .didLoadPageMetadata)  // .didLoadFavicon, // TODO: Bug 1390294
    }

    class func clearSearchIndex(completionHandler: ((Error?) -> Void)? = nil) {
        searchableIndex.deleteAllSearchableItems(completionHandler: completionHandler)
    }

    fileprivate func setUserActivityForTab(_ tab: Tab, url: URL) {
        guard !tab.isIncognito, url.isWebPage(includeDataURIs: false),
            !InternalURL.isValid(url: url)
        else {
            tab.userActivity?.resignCurrent()
            tab.userActivity = nil
            return
        }

        tab.userActivity?.invalidate()

        // Create user activity for browsing a webpage
        let userActivity = NSUserActivity(activityType: Self.browsingActivityType)
        userActivity.title = tab.title
        // Indicate activity should be added to spotlight index
        userActivity.isEligibleForSearch = true
        // Carry url payload instead of using webpageURL in case neeva app is not DB
        userActivity.requiredUserInfoKeys = ["url"]
        userActivity.userInfo = ["url": url.absoluteString]
        // we can set userActivity.keywords = [String] to specify additional queries with which this item can be found in spotlight

        // create rich attributes for spotlight card in place of NSUserActivity properties
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = tab.pageMetadata?.title
        attributes.contentDescription = tab.pageMetadata?.description
        userActivity.contentAttributeSet = attributes
        userActivity.needsSave = true

        DispatchQueue.global(qos: .utility).async {
            let imageData = FaviconResolver(site: Site(url: url, title: "")).fallbackContent.image.pngData()
            userActivity.contentAttributeSet?.thumbnailData = imageData
            userActivity.needsSave = true
        }

        // Set activity as active and makes it available for indexing (if isEligibleForSearch)
        userActivity.becomeCurrent()

        tab.userActivity = userActivity
    }

    class func presentTextSizeView(webView: WKWebView) {
        let bvc = SceneDelegate.getBVC(for: webView)
        bvc.showAsModalOverlaySheet(style: .grouped) {
            TextSizeView(
                model: TextSizeModel(webView: webView)
            ) {
                bvc.overlayManager.hideCurrentOverlay(ofPriority: .modal)
            }
        } onDismiss: {}
    }
}

extension UserActivityHandler: TabEventHandler {
    func tabDidGainFocus(_ tab: Tab) {
        tab.userActivity?.becomeCurrent()
    }

    func tabDidLoseFocus(_ tab: Tab) {
        tab.userActivity?.resignCurrent()
    }

    func tab(_ tab: Tab, didChangeURL url: URL) {
        setUserActivityForTab(tab, url: url)
    }

    func tab(_ tab: Tab, didLoadPageMetadata metadata: PageMetadata) {
        setUserActivityForTab(tab, url: metadata.siteURL)
    }

    func tabDidClose(_ tab: Tab) {
        guard let userActivity = tab.userActivity else {
            return
        }
        tab.userActivity = nil
        userActivity.invalidate()
    }
}

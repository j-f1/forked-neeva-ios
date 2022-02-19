/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Storage
import WebKit

// This cannot be easily imported into extension targets, so we break it out here.
extension SavedTab {
    convenience init(tab: Tab, isSelected: Bool, tabIndex: Int?) {
        assert(Thread.isMainThread)

        var sessionData = tab.sessionData
        if sessionData == nil {
            let currentItem: WKBackForwardListItem! = tab.webView?.backForwardList.currentItem

            // Freshly created web views won't have any history entries at all.
            // If we have no history, abort.
            if currentItem != nil {
                let navigationList = tab.webView?.backForwardList.all ?? []
                let urls = navigationList.compactMap { $0.url }
                let currentPage = -(tab.webView?.backForwardList.forwardList ?? []).count
                let queries = navigationList.map {
                    tab.queryForNavigation.findQueryFor(navigation: $0)
                }

                sessionData = SessionData(
                    currentPage: currentPage, urls: urls,
                    queries: queries.map { $0?.typed },
                    suggestedQueries: queries.map { $0?.suggested },
                    lastUsedTime: tab.lastExecutedTime ?? Date.nowMilliseconds())
            }
        }

        self.init(
            screenshotUUID: tab.screenshotUUID, isSelected: isSelected,
            title: tab.title ?? tab.lastTitle, isPrivate: tab.isIncognito, isPinned: tab.isPinned,
            pinnedTime: tab.pinnedTime,
            faviconURL: tab.displayFavicon?.url, url: tab.url, sessionData: sessionData,
            uuid: tab.tabUUID, rootUUID: tab.rootUUID, parentUUID: tab.parentUUID ?? "",
            tabIndex: tabIndex, parentSpaceID: tab.parentSpaceID ?? "")
    }

    func configureSavedTabUsing(_ tab: Tab, imageStore: DiskImageStore? = nil) -> Tab {
        // Since this is a restored tab, reset the URL to be loaded as that will be handled by the SessionRestoreHandler
        tab.setURL(nil)

        if let faviconURL = faviconURL {
            let icon = Favicon(url: faviconURL, date: Date())
            icon.width = 1
            tab.favicon = icon
        }

        if let screenshotUUID = screenshotUUID,
            let imageStore = imageStore
        {
            tab.screenshotUUID = screenshotUUID
            imageStore.get(screenshotUUID.uuidString) >>== { screenshot in
                if tab.screenshotUUID == screenshotUUID {
                    tab.setScreenshot(screenshot, revUUID: false)
                }
            }
        }

        tab.sessionData = sessionData
        tab.lastTitle = title
        tab.isPinned = isPinned
        tab.pinnedTime = pinnedTime
        tab.parentUUID = parentUUID ?? ""
        tab.tabUUID = UUID ?? ""
        tab.rootUUID = rootUUID ?? ""
        tab.parentSpaceID = parentSpaceID ?? ""

        return tab
    }
}

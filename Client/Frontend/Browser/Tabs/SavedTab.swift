/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import WebKit

class SavedTab: NSObject, NSCoding {
    var isSelected: Bool
    var title: String?
    var url: URL?
    var isPrivate: Bool
    var isPinned: Bool
    var pinnedTime: TimeInterval?
    var sessionData: SessionData?
    var screenshotUUID: UUID?
    var faviconURL: URL?
    var UUID: String?
    var rootUUID: String?
    var parentUUID: String?
    var tabIndex: Int?
    var parentSpaceID: String?

    var jsonDictionary: [String: AnyObject] {
        let title: String = self.title ?? "null"
        let faviconURL: String = self.faviconURL?.absoluteString ?? "null"
        let uuid: String = self.screenshotUUID?.uuidString ?? "null"

        var json: [String: AnyObject] = [
            "title": title as AnyObject,
            "isPrivate": String(self.isPrivate) as AnyObject,
            "isSelected": String(self.isSelected) as AnyObject,
            "faviconURL": faviconURL as AnyObject,
            "screenshotUUID": uuid as AnyObject,
            "url": url as AnyObject,
            "UUID": self.UUID as AnyObject,
            "rootUUID": self.UUID as AnyObject,
            "parentUUID": self.UUID as AnyObject,
            "tabIndex": self.tabIndex as AnyObject,
            "parentSpaceID": self.parentSpaceID as AnyObject,
        ]

        if let sessionDataInfo = self.sessionData?.jsonDictionary {
            json["sessionData"] = sessionDataInfo as AnyObject?
        }

        return json
    }

    init(
        screenshotUUID: UUID?, isSelected: Bool, title: String?, isPrivate: Bool, isPinned: Bool,
        pinnedTime: TimeInterval?,
        faviconURL: URL?, url: URL?, sessionData: SessionData?, uuid: String, rootUUID: String,
        parentUUID: String, tabIndex: Int?, parentSpaceID: String
    ) {
        self.screenshotUUID = screenshotUUID
        self.isSelected = isSelected
        self.title = title
        self.isPrivate = isPrivate
        self.isPinned = isPinned
        self.pinnedTime = pinnedTime
        self.faviconURL = faviconURL
        self.url = url
        self.sessionData = sessionData
        self.UUID = uuid
        self.rootUUID = rootUUID
        self.parentUUID = parentUUID
        self.tabIndex = tabIndex
        self.parentSpaceID = parentSpaceID

        super.init()
    }

    required init(coder: NSCoder) {
        self.sessionData = coder.decodeObject(forKey: "sessionData") as? SessionData
        self.screenshotUUID = coder.decodeObject(forKey: "screenshotUUID") as? UUID
        self.isSelected = coder.decodeBool(forKey: "isSelected")
        self.isPinned = coder.decodeBool(forKey: "isPinned")
        self.pinnedTime = coder.decodeObject(forKey: "pinnedTime") as? TimeInterval
        self.title = coder.decodeObject(forKey: "title") as? String
        self.isPrivate = coder.decodeBool(forKey: "isPrivate")
        self.faviconURL = (coder.decodeObject(forKey: "faviconURL") as? URL)
        self.url = coder.decodeObject(forKey: "url") as? URL
        self.UUID = coder.decodeObject(forKey: "UUID") as? String
        self.rootUUID = coder.decodeObject(forKey: "rootUUID") as? String
        self.parentUUID = coder.decodeObject(forKey: "parentUUID") as? String
        self.tabIndex = coder.decodeObject(forKey: "tabIndex") as? Int
        self.parentSpaceID = coder.decodeObject(forKey: "parentSpaceID") as? String
    }

    func encode(with coder: NSCoder) {
        coder.encode(sessionData, forKey: "sessionData")
        coder.encode(screenshotUUID, forKey: "screenshotUUID")
        coder.encode(isSelected, forKey: "isSelected")
        coder.encode(isPinned, forKey: "isPinned")
        coder.encode(pinnedTime, forKey: "pinnedTime")
        coder.encode(title, forKey: "title")
        coder.encode(isPrivate, forKey: "isPrivate")
        coder.encode(faviconURL, forKey: "faviconURL")
        coder.encode(url, forKey: "url")
        coder.encode(UUID, forKey: "UUID")
        coder.encode(rootUUID, forKey: "rootUUID")
        coder.encode(parentUUID, forKey: "parentUUID")
        coder.encode(tabIndex, forKey: "tabIndex")
        coder.encode(parentSpaceID, forKey: "parentSpaceID")
    }
}

// Copyright Neeva. All rights reserved.

import Foundation
import Storage
import SDWebImageSwiftUI
import SwiftUI
import Shared

/// The intention for a browser primitive is to represent any metadata or entity tied to a url with a card in a heterogenous UI. Tabs are
/// the canonical browser primitive, but Spaces, a single entry in a Space, a History entry, a product in a web page can be a browser
/// primitive as well. The framework here tries to establish rules around how these primitives should be represented and how they can
/// interact with the user and each other. Ex: Dragging a product on top of a tab card should save that product as metadata in the tab,
/// or links within a page can be cards and dragging them to a space card should add them to the Space.

/// If you are adding a new BrowserPrimitive via an extension, think of the best Managers for that primitive and add those, too. Different
/// managers for the same primitive do not have to be of the same type. Ex: Clicking on a History item should navigate to that url in the
/// current tab (SelectingManager is Tab), but swiping it away should delete it from history (ClosingManager is History DB)

/// As a principle, BrowserPrimitive should stay as a data model rather and a ViewModel. Any details about presentation of the primitive
/// should live inside the corresponding CardDetails. (That's why we have image as a UIImage but thumbnail as a View. Thumbnail can
/// be derived from any of the data provided by the primitive. (We can choose image as the thumbnail but can also fallback to using a
/// mediaUrl inside the pageMetadata). This is also why CardDetails is the DropDelegate rather than the BrowserPrimitive.

protocol BrowserPrimitive {
    var primitiveUrl: URL? { get }
    var displayTitle: String { get }
    var displayFavicon: Favicon? { get }
    var image: UIImage? { get }
    var pageMetadata: PageMetadata? { get }
}

protocol Closeable {
    associatedtype Manager: ClosingManager where Manager.Item == Self

    func close(with manager: Manager)
}

protocol Selectable {
    associatedtype Manager: SelectingManager where Manager.Item == Self

    func select(with manager: Manager)
}

protocol AccessingManagerProvider {
    associatedtype Manager : AccessingManager
    var manager: Manager { get set }
}

protocol AccessingManager {
    associatedtype Item
    func get(for id: String) -> Item?
    func getAll() -> [Item]
}

protocol ClosingManagerProvider {
    associatedtype Manager : ClosingManager
    var manager: Manager { get set }
}

protocol ClosingManager {
    associatedtype Item
    func close(_ item: Item)
}

protocol SelectingManagerProvider {
    associatedtype Manager : SelectingManager
    var manager: Manager { get set }
}

protocol SelectingManager {
    associatedtype Item
    func select(_ item: Item)
}

// MARK: Tab: BrowserPrimitive

extension Tab: Closeable, Selectable, BrowserPrimitive {
    var primitiveUrl: URL? {
        url
    }

    var image: UIImage? {
        screenshot
    }

    typealias Manager = TabManager

    func close(with manager: TabManager) {
        manager.close(self)
    }

    func select(with manager: TabManager) {
        manager.select(self)
    }
}

extension TabManager: ClosingManager, SelectingManager, AccessingManager {
    typealias Item = Tab

    func close(_ tab: Tab) {
        removeTabAndUpdateSelectedIndex(tab)
    }

    func select(_ tab: Tab) {
        selectTab(tab)
    }

    func get(for id: String) -> Tab? {
        getTabForUUID(uuid: id)
    }

    func getAll() -> [Tab] {
        let isPrivate = selectedTab?.isPrivate ?? false
        return tabs.filter{$0.isPrivate == isPrivate}
    }
}

// MARK: Space: BrowserPrimitive
extension Space: BrowserPrimitive {
    var primitiveUrl: URL? {
        url
    }

    var displayTitle: String {
        name
    }

    var displayFavicon: Favicon? {
        nil
    }

    var image: UIImage? {
        if let thumbnail = thumbnail?.dataURIBody {
            return UIImage(data: thumbnail)
        }
        return nil
    }

    var pageMetadata: PageMetadata? {
        return nil
    }
}

extension SpaceStore: AccessingManager {
    typealias Item = Space

    func get(for id: String) -> Space? {
        allSpaces.first(where: { $0.id.id == id })
    }

    func getAll() -> [Space] {
        allSpaces
    }
}

// MARK: Site: BrowserPrimitive
extension Site: BrowserPrimitive {
    var primitiveUrl: URL? {
        URL(string: url)
    }

    var displayTitle: String {
        title
    }

    var displayFavicon: Favicon? {
        icon
    }

    var image: UIImage? {
        nil
    }

    var pageMetadata: PageMetadata? {
        metadata
    }
}



class SiteFetcher : AccessingManager, ObservableObject {
    typealias Item = Site

    @Published var cache: [String: Site] = [:]
    var sites: [Site?] = [] {
        didSet {
            self.cache = self.sites.compactMap { $0 }.reduce(into: [:]) { dict, site in
                dict[site!.url] = site
            }
        }
    }

    func load(url: String, profile: Profile) {
        let sql = profile.metadata
        sql.metadata(for: URL(string: url)!).uponQueue(.main) { val in
            guard let metadata = val.successValue?.asArray().first else {
                return
            }

            let site = Site(url: url, title: metadata?.title ?? "")
            site.metadata = metadata
            self.sites.append(site)
        }
    }

    func get(for id: String) -> Site? {
        cache[id]
    }

    func getAll() -> [Site] {
        Array(cache.values)
    }
}

extension Tab: SelectingManager {
    typealias Item = Site

    func select(_ item: Site) {
        loadRequest(URLRequest(url: URL(string: item.url)!))
    }
}

typealias Journey = [Site: [BrowserPrimitive]]

// MARK: Journey: BrowserPrimitive

extension Journey: BrowserPrimitive {
    var primitiveUrl: URL? {
        guard count > 0 else {
            assert(false)
            return nil
        }

        guard count > 1 else {
            return keys.first!.primitiveUrl
        }

        if isNeevaSearchJourney {
            return NeevaConstants.appURL
        }


        if keysCollapsedAcrossDomains.count == 1  {
            return keysCollapsedAcrossDomains.first
        }

        return keys.first!.primitiveUrl
    }

    var displayTitle: String {
        guard count > 0 else {
            assert(false)
            return ""
        }

        guard count > 1 else {
            return keys.first!.displayTitle
        }

        if isNeevaSearchJourney {
            return keys.map {neevaSearchEngine.queryForSearchURL($0.primitiveUrl)}.reduce("") { $0 + $1! + " " }
        }

        if keysCollapsedAcrossDomains.count == 1, let domain = keysCollapsedAcrossDomains.first?.baseDomain  {
            return domain.capitalizingFirstLetter()
        }

        return keys.first!.displayTitle
    }

    var displayFavicon: Favicon? {
        nil
    }

    var image: UIImage? {
        nil
    }

    var pageMetadata: PageMetadata? {
        nil
    }

    var isNeevaSearchJourney : Bool {
        keys.allSatisfy({$0.url.hasPrefix(NeevaConstants.appSearchURL.absoluteString)})
    }

    var keysCollapsedAcrossDomains : [URL] {
        Array(keys.reduce(into: [:]) { $0[($1.primitiveUrl?.domainURL)!] =
            ($0[($1.primitiveUrl?.domainURL)!] ?? 0) + 1 }.keys)
    }
}

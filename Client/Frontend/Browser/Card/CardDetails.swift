// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Defaults
import Foundation
import SDWebImageSwiftUI
import Shared
import Storage
import SwiftUI

protocol SelectableThumbnail {
    associatedtype ThumbnailView: View

    var thumbnail: ThumbnailView { get }
    func onSelect()
}

protocol CardDetails: ObservableObject, DropDelegate, SelectableThumbnail, Identifiable, Equatable {
    associatedtype Item: BrowserPrimitive
    associatedtype FaviconViewType: View

    var id: String { get }
    var closeButtonImage: UIImage? { get }
    var title: String { get }
    var description: String? { get }
    var accessibilityLabel: String { get }
    var defaultIcon: String? { get }
    var favicon: FaviconViewType { get }
    var isSelected: Bool { get }
    var thumbnailDrawsHeader: Bool { get }
    var isSharedWithGroup: Bool { get }
    var isSharedPublic: Bool { get }
    var ACL: SpaceACLLevel { get }

    func onClose()
}

extension CardDetails {
    var isSelected: Bool {
        false
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }

    var thumbnailDrawsHeader: Bool {
        true
    }

    var defaultIcon: String? {
        nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension CardDetails
where
    Item: Selectable, Self: SelectingManagerProvider, Self.Manager.Item == Item,
    Manager: AccessingManager
{
    func onSelect() {
        if let item = manager.get(for: id) {
            manager.select(item)
        }
    }
}

extension CardDetails
where
    Item: Closeable, Self: ClosingManagerProvider, Self.Manager.Item == Item,
    Manager: AccessingManager
{

    var closeButtonImage: UIImage? {
        UIImage(systemName: "xmark")
    }

    func onClose() {
        if let item = manager.get(for: id) {
            manager.close(item)
        }
    }
}

extension CardDetails where Self: AccessingManagerProvider, Self.Manager.Item == Item {
    var title: String {
        manager.get(for: id)?.displayTitle ?? ""
    }

    var description: String? {
        return manager.get(for: id)?.pageMetadata?.description
    }

    var isSharedWithGroup: Bool { manager.get(for: id)?.isSharedWithGroup ?? false }
    var isSharedPublic: Bool { manager.get(for: id)?.isSharedPublic ?? false }
    var ACL: SpaceACLLevel { manager.get(for: id)?.ACL ?? .owner }

    @ViewBuilder var thumbnail: some View {
        if let image = manager.get(for: id)?.image {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color.white
        }
    }

    @ViewBuilder var favicon: some View {
        if let item = manager.get(for: id) {
            if let favicon = item.displayFavicon {
                FaviconView(forFavicon: favicon)
                    .background(Color.white)
            } else if let icon = defaultIcon {
                Image(systemName: icon)
            } else if let url = item.primitiveUrl {
                FaviconView(forSiteUrl: url)
                    .background(Color.white)
            }
        }
    }
}

public class TabCardDetails: CardDetails, AccessingManagerProvider,
    ClosingManagerProvider, SelectingManagerProvider
{
    typealias Item = Tab
    typealias Manager = TabManager

    public let id: String
    private var isPinnedSubscription: AnyCancellable?

    var manager: TabManager
    var isChild: Bool

    private var tab: Tab? {
        manager.get(for: id)
    }

    var isPinned: Bool {
        tab?.isPinned ?? false
    }

    var pinnedTime: Double? {
        tab?.pinnedTime
    }

    var url: URL? {
        tab?.url ?? tab?.sessionData?.currentUrl
    }

    var closeButtonImage: UIImage? {
        FeatureFlag[.tabGroupsPinning] && isPinned
            ? UIImage(systemName: "pin.fill") : UIImage(systemName: "xmark")
    }

    var isSelected: Bool {
        self.manager.selectedTab?.tabUUID == id
    }

    var rootID: String? {
        tab?.rootUUID
    }

    var accessibilityLabel: String {
        "\(title), Tab"
    }

    var thumbnailDrawsHeader: Bool {
        false
    }

    // Avoiding keeping a reference to classes both to minimize surface area these Card classes have
    // access to, but also to not worry about reference copying while using CardDetails for View updates.
    init(tab: Tab, manager: TabManager, isChild: Bool = false) {
        self.id = tab.id
        self.manager = manager
        self.isChild = isChild

        isPinnedSubscription = tab.$isPinned.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func performDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: ["public.url"]) else {
            return false
        }

        let items = info.itemProviders(for: ["public.url"])
        for item in items {
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        self.manager.get(for: self.id)?.loadRequest(URLRequest(url: url))
                    }
                }
            }
        }

        return true
    }

    func onClose() {
        if let item = tab, !item.isPinned {
            manager.close(item)
        }
    }

    @ViewBuilder func contextMenu() -> some View {
        if !(tab?.isIncognito ?? false) {
            Button { [self] in
                guard let url = url, let tab = tab else { return }
                let newTab = manager.addTab(
                    URLRequest(url: url), afterTab: tab, isPrivate: tab.isIncognito)
                newTab.rootUUID = UUID().uuidString
                manager.selectTab(newTab, previous: tab)
            } label: {
                Label("Duplicate Tab", systemSymbol: .plusSquareOnSquare)
            }.disabled(url == nil)

            Button { [self] in
                guard let url = url, let tab = tab else { return }
                let newTab = manager.addTab(URLRequest(url: url), afterTab: tab, isPrivate: true)
                newTab.rootUUID = UUID().uuidString
                manager.selectTab(newTab, previous: tab)
            } label: {
                Label("Open in Incognito", image: "incognito")
            }.disabled(url == nil)

            Button(action: { [self] in
                tab?.showAddToSpacesSheet()
            }) {
                Label("Save to Spaces", systemSymbol: .bookmark)
            }.disabled(tab == nil)

            if let tab = tab,
                tab.canonicalURL?.displayURL != nil,
                let bvc = tab.browserViewController
            {
                Button {
                    tab.browserViewController?.share(tab: tab, from: bvc.view, presentableVC: bvc)
                } label: {
                    Label("Share", systemSymbol: .squareAndArrowUp)
                }
            } else {
                Button(action: {}) {
                    Label("Share", systemSymbol: .squareAndArrowUp)
                }.disabled(true)
            }

            if isChild {
                Button(
                    action: { [self] in
                        ClientLogger.shared.logCounter(.tabRemovedFromGroup)
                        manager.get(for: id)?.rootUUID = UUID().uuidString
                        manager.tabsUpdatedPublisher.send()
                    },
                    label: {
                        Label("Remove from group", systemSymbol: .arrowUpForwardSquare)
                    }
                )
            }

            Button(
                action: { [self] in
                    manager.get(for: id)?.pinnedTime =
                        (isPinned ? nil : Date().timeIntervalSinceReferenceDate)
                    manager.get(for: id)?.isPinned.toggle()
                },
                label: {
                    isPinned
                        ? Label("Unpin tab", systemSymbol: .pinSlash)
                        : Label("Pin tab", systemSymbol: .pin)
                }
            )

            Divider()

            if #available(iOS 15.0, *) {
                Button(
                    role: .destructive,
                    action: { [self] in
                        if let item = tab {
                            manager.close(item)
                        }
                    },
                    label: {
                        Label("Close Tab", systemSymbol: .trash)
                    }
                )
            } else {
                Button(
                    action: { [self] in
                        if let item = tab {
                            manager.close(item)
                        }
                    },
                    label: {
                        Label("Close Tab", systemSymbol: .trash)
                    }
                )
            }

        }
    }
}

class SpaceEntityThumbnail: CardDetails, AccessingManagerProvider {
    typealias Item = SpaceEntityData
    typealias Manager = Space

    var manager: Space {
        SpaceStore.shared.get(for: spaceID) ?? SpaceStore.suggested.get(for: spaceID)!
    }

    let spaceID: String
    var data: SpaceEntityData

    var id: String
    var closeButtonImage: UIImage? = nil
    var accessibilityLabel: String = "Space Item"

    var ACL: SpaceACLLevel {
        manager.ACL
    }

    private var imageThumbnailModel: ImageThumbnailModel?

    var isImage: Bool {

        guard let pathExtension = data.url?.pathExtension else {
            return false
        }

        return pathExtension == "jpeg"
            || pathExtension == "jpg"
            || pathExtension == "png"
            || pathExtension == "gif"
    }

    var richEntityPreviewURL: URL? {
        guard case .richEntity(let richEntity) = data.previewEntity else {
            return nil
        }
        let spaceURL = NeevaConstants.appSpacesURL.appendingPathComponent(spaceID).absoluteString
        return URL(string: "\(spaceURL)#kg-entity-\(richEntity.id)")

    }

    var productPreviewURL: URL? {
        guard case .retailProduct(let product) = data.previewEntity else {
            return nil
        }
        let spaceURL = NeevaConstants.appSpacesURL.appendingPathComponent(spaceID).absoluteString
        return URL(string: "\(spaceURL)#retail-widget-\(product.id)")
    }

    var techDocURL: URL? {
        guard case .techDoc(let techDoc) = data.previewEntity else {
            return nil
        }
        let spaceURL = NeevaConstants.appSpacesURL.appendingPathComponent(spaceID).absoluteString
        return URL(string: "\(spaceURL)#techdoc-\(techDoc.id)-\(techDoc.id)")
    }

    var previewURL: URL? {
        techDocURL ?? productPreviewURL ?? richEntityPreviewURL
    }

    init(data: SpaceEntityData, spaceID: String) {
        self.spaceID = spaceID
        self.data = data
        self.id = data.id
        if let thumbnailData = data.thumbnail?.dataURIBody {
            self.imageThumbnailModel = .init(imageData: thumbnailData)
        }
    }

    func webImage(url: URL) -> some View {
        WebImage(
            url: url,
            context: [
                .imageThumbnailPixelSize: CGSize(
                    width: DetailsViewUX.DetailThumbnailSize * 4,
                    height: DetailsViewUX.DetailThumbnailSize * 4)
            ]
        )
        .resizable()
        .aspectRatio(contentMode: .fill)
    }

    @ViewBuilder var thumbnail: some View {
        if case .recipe(let recipe) = data.previewEntity,
            let imageURL = URL(string: recipe.imageURL)
        {
            webImage(url: imageURL)
        } else if case .richEntity(let richEntity) = data.previewEntity,
            let imageURL = richEntity.imageURL
        {
            webImage(url: imageURL)
        } else if case .newsItem(let newsItem) = data.previewEntity,
            let imageURL = newsItem.thumbnailURL
        {
            webImage(url: imageURL)
        } else if isImage, let imageURL = data.url {
            webImage(url: imageURL)
        } else if let imageThumbnailModel = imageThumbnailModel {
            ImageThumbnailView(model: imageThumbnailModel)
        } else {
            GeometryReader { geom in
                Symbol(decorative: .bookmarkOnBookmark, size: geom.size.width / 3)
                    .foregroundColor(Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.spaceIconBackground)
            }
        }
    }

    func onClose() {}
    func onSelect() {}
}

class SpaceCardDetails: CardDetails, AccessingManagerProvider, ThumbnailModel {
    typealias Item = Space
    typealias Manager = SpaceStore
    typealias Thumbnail = SpaceEntityThumbnail

    @Published var manager: SpaceStore
    @Published var isShowingDetails = false

    var id: String
    var closeButtonImage: UIImage? = nil
    @Published var allDetails: [SpaceEntityThumbnail] = []

    var accessibilityLabel: String {
        "\(title), Space"
    }

    var space: Space? {
        manager.get(for: id)
    }

    private init(id: String, manager: SpaceStore) {
        self.id = id
        self.manager = manager

        updateDetails()
    }

    convenience init(space: Space, manager: SpaceStore) {
        self.init(id: space.id.id, manager: manager)
    }

    var thumbnail: some View {
        VStack(spacing: 0) {
            ThumbnailGroupView(model: self)
            HStack {
                Spacer(minLength: 12)
                Text(title)
                    .withFont(.labelMedium)
                    .lineLimit(1)
                    .foregroundColor(Color.label)
                    .frame(height: CardUX.HeaderSize)
                if let space = space, space.isPublic {
                    Symbol(decorative: .link, style: .labelMedium)
                        .foregroundColor(.secondaryLabel)
                } else if let space = space, space.isShared {
                    Symbol(decorative: .person2Fill, style: .labelMedium)
                        .foregroundColor(.secondaryLabel)
                }
                Spacer(minLength: 12)
            }
        }.shadow(radius: 0)
    }

    func updateDetails() {
        allDetails =
            manager.get(for: id)?.contentData?
            .map { SpaceEntityThumbnail(data: $0, spaceID: id) } ?? []
    }

    func onSelect() {
        isShowingDetails = true
    }

    func onClose() {}

    func performDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: ["public.text", "public.url"]) else {
            return false
        }

        let items = info.itemProviders(for: ["public.url"])
        for item in items {
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, let space = self.manager.get(for: self.id) {
                    DispatchQueue.main.async {
                        let request = AddToSpaceRequest(
                            title: "Link from \(url.baseDomain ?? "page")",
                            description: "", url: url)
                        request.addToExistingSpace(id: space.id.id, name: space.name)
                    }
                }
            }
        }

        return true
    }
}

class SiteCardDetails: CardDetails, AccessingManagerProvider {
    typealias Item = Site
    typealias Manager = SiteFetcher

    @Published var manager: SiteFetcher
    var anyCancellable: AnyCancellable? = nil
    var id: String
    var closeButtonImage: UIImage?
    var tabManager: TabManager

    var accessibilityLabel: String {
        "\(title), Link"
    }

    init(url: URL, fetcher: SiteFetcher, tabManager: TabManager) {
        self.id = url.absoluteString
        self.manager = fetcher
        self.tabManager = tabManager

        self.anyCancellable = fetcher.objectWillChange.sink { [weak self] (_) in
            self?.objectWillChange.send()
        }

        fetcher.load(url: url, profile: tabManager.profile)
    }

    func thumbnail(size: CGFloat) -> some View {
        return WebImage(
            url:
                URL(string: manager.get(for: id)?.pageMetadata?.mediaURL ?? "")
        )
        .resizable().aspectRatio(contentMode: .fill)
    }

    func onSelect() {
        guard let site = manager.get(for: id) else {
            return
        }

        tabManager.selectedTab?.select(site)
    }

    func onClose() {}
}

// TabGroupCardDetails are not to be used for storing data because they can be recreated.
class TabGroupCardDetails: CardDetails, AccessingManagerProvider, ClosingManagerProvider,
    ThumbnailModel
{
    typealias Item = TabGroup
    typealias Manager = TabGroupManager

    @Default(.tabGroupExpanded) private var tabGroupExpanded: Set<String>

    @Published var manager: TabGroupManager
    @Published var isShowingDetails = false
    var isExpanded: Bool {
        get {
            tabGroupExpanded.contains(id)
        }
        set {
            if newValue {
                tabGroupExpanded.insert(id)
            } else {
                tabGroupExpanded.remove(id)
            }
        }
    }
    var id: String
    var isSelected: Bool {
        manager.tabManager.selectedTab?.rootUUID == id
    }

    var isPinned: Bool {
        return allDetails.contains {
            $0.isPinned
        }
    }

    var pinnedTime: Double? {
        let pinnedTimeList = allDetails.filter {
            $0.isPinned
        }.map {
            $0.pinnedTime ?? 0
        }

        return pinnedTimeList.min()
    }

    var customTitle: String? {
        get {
            Defaults[.tabGroupNames][id] ?? manager.get(for: id)?.inferredTitle
        }
        set {
            Defaults[.tabGroupNames][id] = newValue
            objectWillChange.send()
        }
    }

    var defaultTitle: String? {
        manager.get(for: id)?.displayTitle
    }

    var title: String {
        Defaults[.tabGroupNames][id] ?? manager.get(for: id)?.displayTitle ?? ""
    }

    @Published var allDetails: [TabCardDetails] = []

    var thumbnailDrawsHeader: Bool {
        false
    }

    var accessibilityLabel: String {
        "\(title), Tab Group"
    }

    var defaultIcon: String? {
        id == manager.get(for: id)?.children.first?.parentSpaceID
            ? "bookmark.fill" : "square.grid.2x2.fill"
    }

    init(tabGroup: TabGroup, tabGroupManager: TabGroupManager) {
        self.id = tabGroup.id
        self.manager = tabGroupManager

        allDetails =
            manager.get(for: id)?.children
            .sorted(by: { lhs, rhs in
                if lhs.isPinned && rhs.isPinned {
                    return lhs.pinnedTime! < rhs.pinnedTime!
                } else if lhs.isPinned && !rhs.isPinned {
                    return true
                } else if !lhs.isPinned && rhs.isPinned {
                    return false
                } else {
                    return false
                }
            })
            .map({
                TabCardDetails(
                    tab: $0,
                    manager: manager.tabManager,
                    isChild: true)
            }) ?? []
    }

    var thumbnail: some View {
        return ThumbnailGroupView(model: self)
    }

    func onSelect() {
        isShowingDetails = true
    }

    func onClose(showToast: Bool) {
        if let item = manager.get(for: id) {
            manager.close(item, showToast: showToast)
        }
    }
}

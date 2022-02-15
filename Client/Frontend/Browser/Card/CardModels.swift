// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Defaults
import Shared
import Storage
import SwiftUI

protocol ThumbnailModel: ObservableObject {
    associatedtype Thumbnail: SelectableThumbnail
    var allDetails: [Thumbnail] { get }
}

protocol CardModel: ThumbnailModel {
    associatedtype Manager: AccessingManager
    associatedtype Details: CardDetails where Details.Item == Manager.Item
    var manager: Manager { get }
    var allDetails: [Details] { get set }
    var allDetailsWithExclusionList: [Details] { get }

    func onDataUpdated()
}

class TabCardModel: CardModel {
    private var onViewUpdate: () -> Void = {}
    var manager: TabManager
    private var groupManager: TabGroupManager
    private var subscription: AnyCancellable? = nil

    @Published var allDetails: [TabCardDetails] = []
    @Published private(set) var allDetailsWithExclusionList: [TabCardDetails] = []
    @Published private(set) var selectedTabID: String? = nil
    @Default(.tabGroupExpanded) private var tabGroupExpanded: Set<String>

    var normalDetails: [TabCardDetails] {
        allDetails.filter {
            manager.get(for: $0.id)?.isIncognito == false
        }
    }

    var incognitoDetails: [TabCardDetails] {
        allDetails.filter {
            manager.get(for: $0.id)?.isIncognito == true
        }
    }

    init(manager: TabManager, groupManager: TabGroupManager) {
        self.manager = manager
        self.groupManager = groupManager
        // Process updates to the TabManager state asynchronously. This way we wait
        // until after `tabs` has been updated before we do any work.
        self.subscription = manager.tabsUpdatedPublisher.filter({ [weak self] in
            self?.manager.didRestoreAllTabs ?? false
        }).sink { [weak self] in
            self?.onDataUpdated()
        }
    }

    struct Row: Identifiable {
        var id: Set<String> { Set(cells.map(\.id)) }
        var numTabsInRow: Int {
            cells.reduce(0, {x, y in
                x + y.numTabs
            })
        }

        enum Cell: Identifiable {
            case tab(TabCardDetails)
            case tabGroupInline(TabGroupCardDetails)
            case tabGroupGridRow(TabGroupCardDetails, Range<Int>)

            var id: String {
                switch self {
                case .tab(let details):
                    return details.id
                case .tabGroupInline(let details):
                    return details.id
                case .tabGroupGridRow(let details, let range):
                    return details.allDetails[range].reduce("") { $0 + $1.id + ":" }
                }
            }

            var isSelected: Bool {
                switch self {
                case .tab(let details):
                    return details.isSelected
                case .tabGroupInline(let details):
                    return details.isSelected
                case .tabGroupGridRow(let details, let range):
                    return details.allDetails[range].contains { $0.isSelected }
                }
            }

            var numTabs: Int {
                switch self {
                case .tab(_):
                    return 1
                case .tabGroupInline(let details):
                    return details.allDetails.count
                case .tabGroupGridRow(let details, _):
                    return details.allDetails.count
                }
            }
        }
        var cells: [Cell]
    }

    func buildRows(incognito: Bool, tabGroupModel: TabGroupCardModel, maxCols: Int) -> [Row] {
        // When the number of tabs in a tab group decreases and makes the group
        // unable to expand, we remove the group from the expanded list. A side-effect
        // of this resolves a problem where TabGroupHeader doesn't hide arrows button
        // when the number of tabs drops below maxCols.
        tabGroupExpanded.forEach { groupID in
            if let tabGroup = tabGroupModel.allDetails.first(where: { groupID == $0.id }), tabGroup.allDetails.count <= maxCols {
                tabGroupExpanded.remove(groupID)
            }
        }

        return allDetails.filter { tabCard in
            let tab = tabCard.manager.get(for: tabCard.id)!
            return
                (tabGroupModel.representativeTabs.contains(tab)
                || allDetailsWithExclusionList.contains { $0.id == tabCard.id })
                && tab.isIncognito == incognito
        }.reduce(into: []) { partialResult, details in
            let tabGroup = tabGroupModel.allDetails.first(where: { $0.id == details.rootID })
            if partialResult.isEmpty || partialResult.last!.numTabsInRow >= maxCols
                || tabGroup != nil
            {
                if let tabGroup = tabGroup {
                    if tabGroup.isExpanded {
                        // tabGroupGridRow always occupies a row by itself.
                        for index in stride(from: 0, to: tabGroup.allDetails.count, by: maxCols) {
                            var max = index + maxCols
                            if max > tabGroup.allDetails.count {
                                max = tabGroup.allDetails.count
                            }
                            let range = index..<max
                            partialResult.append(
                                Row(cells: [Row.Cell.tabGroupGridRow(tabGroup, range)]))
                        }
                    } else {
                        // If there's enough remaining columns, fit the tab group in the same row with individual tabs.
                        // Otherwise, build a horizontal scroll view in the next row.
                        if (tabGroup.allDetails.count + (partialResult.last?.numTabsInRow ?? 0)) <= maxCols && !partialResult.isEmpty {
                            partialResult[partialResult.endIndex - 1].cells.append(.tabGroupInline(tabGroup))
                        } else {
                            partialResult.append(Row(cells: [Row.Cell.tabGroupInline(tabGroup)]))
                        }
                    }
                } else {
                    partialResult.append(Row(cells: [.tab(details)]))
                }
                // Insert a new row (following expanded tab group) for individual tabs
                if tabGroup != nil && tabGroup!.isExpanded {
                    partialResult.append(Row(cells: []))
                }
            } else {
                partialResult[partialResult.endIndex - 1].cells.append(.tab(details))
            }
        }.filter { !$0.cells.isEmpty }
    }

    func onDataUpdated() {
        groupManager.updateTabGroups()
        allDetails = manager.getAll()
            .map { TabCardDetails(tab: $0, manager: manager) }

        allDetailsWithExclusionList = manager.getAll().filter {
            !groupManager.childTabs.contains($0)
        }
        .map { TabCardDetails(tab: $0, manager: manager) }
        selectedTabID = manager.selectedTab?.tabUUID ?? ""
        onViewUpdate()
    }

    func getAllDetails(matchingIncognitoState: Bool?) -> [TabCardDetails] {
        if let matchingIncognitoState = matchingIncognitoState {
            return matchingIncognitoState ? incognitoDetails : normalDetails
        } else {
            return allDetails
        }
    }
}

func getLogCounterAttributesForSpaces(details: SpaceCardDetails?) -> [ClientLogCounterAttribute] {
    var attributes = EnvironmentHelper.shared.getAttributes()
    attributes.append(
        ClientLogCounterAttribute(
            key: LogConfig.SpacesAttribute.isPublic,
            value: String(details?.isSharedPublic ?? false)))
    if details?.isSharedPublic == true {
        attributes.append(
            ClientLogCounterAttribute(
                key: LogConfig.SpacesAttribute.spaceID,
                value: String(details?.id ?? "")))
    }
    attributes.append(
        ClientLogCounterAttribute(
            key: LogConfig.SpacesAttribute.isShared,
            value: String(details?.isSharedWithGroup ?? false)))
    attributes.append(
        ClientLogCounterAttribute(
            key: LogConfig.SpacesAttribute.numberOfSpaceEntities,
            value: String(details?.allDetails.count ?? 1)
        )

    )
    return attributes
}

class SpaceCardModel: CardModel {
    @Published private(set) var manager = SpaceStore.shared
    @Published var allDetails: [SpaceCardDetails] = [] {
        didSet {
            allDetailsWithExclusionList = allDetails
        }
    }
    @Published private(set) var allDetailsWithExclusionList: [SpaceCardDetails] = []
    @Published var detailedSpace: SpaceCardDetails? {
        willSet {
            guard let space = detailedSpace, newValue == nil else {
                return
            }

            space.isShowingDetails = false
        }

        didSet {
            guard detailedSpace == nil else {
                ClientLogger.shared.logCounter(
                    .SpacesDetailUIVisited,
                    attributes:
                        getLogCounterAttributesForSpaces(details: detailedSpace!))
                // Collect separately. View definition depends on aggregate stats policy
                ClientLogger.shared.logCounter(
                    .space_app_view,
                    attributes:
                        getLogCounterAttributesForSpaces(details: detailedSpace!))
                return
            }

            if let id = spaceNeedsRefresh {
                manager.refreshSpace(spaceID: id)
                spaceNeedsRefresh = nil
            }
        }
    }
    @Published var updatedItemIDs = [String]()
    @Published var filterState: SpaceFilterState = .allSpaces

    var detailsMatchingFilter: [SpaceCardDetails] {
        let spaces = allDetails.filter {
            NeevaFeatureFlags[.enableSpaceDigestCard] || $0.id != SpaceStore.dailyDigestID
        }

        switch filterState {
        case .allSpaces:
            return spaces
        case .ownedByMe:
            return spaces.filter { $0.space?.userACL == .owner }
        }
    }

    private var onViewUpdate: () -> Void = {}
    var thumbnailURLCandidates = [URL: [URL]]()
    private var anyCancellable: AnyCancellable? = nil
    private var recommendationSubscription: AnyCancellable? = nil
    private var editingSubscription: AnyCancellable? = nil
    private var detailsSubscriptions: Set<AnyCancellable> = Set()
    private var spaceNeedsRefresh: String? = nil

    init(manager: SpaceStore = SpaceStore.shared) {
        self.manager = manager

        NeevaUserInfo.shared.$isUserLoggedIn.sink { isLoggedIn in
            DispatchQueue.main.async {
                // Refresh to get spaces for logged in users and to clear cache for logged out users
                SpaceStore.shared.refresh()
            }

            if !isLoggedIn {
                self.allDetails = []
            }
        }.store(in: &detailsSubscriptions)

        self.anyCancellable = manager.$state.sink { [weak self] state in
            guard let self = self, self.detailedSpace == nil, case .ready = state,
                manager.updatedSpacesFromLastRefresh.count > 0
            else {
                return
            }

            if manager.updatedSpacesFromLastRefresh.count == 1,
                let id = manager.updatedSpacesFromLastRefresh.first?.id.id,
                let indexInStore = manager.allSpaces.firstIndex(where: { $0.id.id == id }),
                let indexInDetails = self.allDetails.firstIndex(where: { $0.id == id })
            {
                // If only one space is updated and it exists inside the current details, then just
                // update its contents and move it to the right place, instead of resetting all.
                self.allDetails.first(where: { $0.id == id })?.updateDetails()
                if indexInStore != indexInDetails {
                    let indices: IndexSet = [indexInDetails]
                    self.allDetails.move(fromOffsets: indices, toOffset: indexInStore)
                }
                return
            }

            DispatchQueue.main.async {
                self.allDetails = manager.getAll().map {
                    SpaceCardDetails(space: $0, manager: manager)
                }
                self.allDetails.forEach { details in
                    let detailID = details.id
                    details.$isShowingDetails.sink { [weak self] showingDetails in
                        if showingDetails {
                            withAnimation {
                                self?.detailedSpace =
                                    self?.allDetails.first(where: { $0.id == detailID })
                            }
                        }
                    }.store(in: &self.detailsSubscriptions)
                }

                self.onViewUpdate()
                self.detailedSpace = self.allDetails.first { $0.isShowingDetails }
                self.objectWillChange.send()
            }
        }
    }

    func onDataUpdated() {
        allDetails = manager.getAll().map {
            SpaceCardDetails(space: $0, manager: manager)
        }
        allDetails.forEach { details in
            let detailID = details.id
            details.$isShowingDetails.sink { [weak self] showingDetails in
                if showingDetails {
                    withAnimation {
                        self?.detailedSpace =
                            self?.allDetails.first(where: { $0.id == detailID })
                    }
                }
            }.store(in: &detailsSubscriptions)
        }
    }

    func add(spaceID: String, url: String, title: String, description: String? = nil) {
        DispatchQueue.main.async {
            let request = AddToSpaceWithURLRequest(
                spaceID: spaceID, url: url, title: title, description: description)
            request.$state.sink { state in
                self.spaceNeedsRefresh = spaceID
            }.cancel()
        }
    }

    func updateSpaceEntity(
        spaceID: String, entityID: String, title: String, snippet: String, thumbnail: String? = nil
    ) {
        DispatchQueue.main.async {
            let request = UpdateSpaceEntityRequest(
                spaceID: spaceID, entityID: entityID, title: title, snippet: snippet,
                thumbnail: thumbnail)
            request.$state.sink { state in
                self.spaceNeedsRefresh = spaceID
            }.cancel()
        }
    }

    func claimGeneratedItem(spaceID: String, entityID: String) {
        DispatchQueue.main.async {
            let request = ClaimGeneratedItem(spaceID: spaceID, entityID: entityID)
            request.$state.sink { state in
                self.spaceNeedsRefresh = spaceID
            }.cancel()
        }
    }

    func delete(
        space spaceID: String, entities: [SpaceEntityThumbnail], from scene: UIScene,
        undoDeletion: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            let request = DeleteSpaceItemsRequest(spaceID: spaceID, ids: entities.map { $0.id })
            request.$state.sink { state in
                self.spaceNeedsRefresh = spaceID
            }.cancel()

            ToastDefaults().showToastForRemoveFromSpace(
                bvc: SceneDelegate.getBVC(with: scene), request: request
            ) {
                undoDeletion()

                // Undo deletion of Space item
                entities.forEach { entity in
                    self.add(
                        spaceID: spaceID, url: entity.data.url?.absoluteString ?? "",
                        title: entity.title, description: entity.description)
                }
            } retryDeletion: { [weak self] in
                guard let self = self else { return }
                self.delete(
                    space: spaceID, entities: entities, from: scene, undoDeletion: undoDeletion)
            }
        }
    }

    func reorder(space spaceID: String, entities: [String]) {
        DispatchQueue.main.async {
            let request = ReorderSpaceRequest(spaceID: spaceID, ids: entities)
            request.$state.sink { state in
                self.spaceNeedsRefresh = spaceID
            }.cancel()
        }
    }

    func changePublicACL(space: Space, add: Bool) {
        DispatchQueue.main.async {
            if add {
                let request = AddPublicACLRequest(spaceID: space.id.id)
                request.$state.sink { state in
                    self.spaceNeedsRefresh = space.id.id
                    space.isPublic = true
                    self.objectWillChange.send()
                }.cancel()
            } else {
                let request = DeletePublicACLRequest(spaceID: space.id.id)
                request.$state.sink { state in
                    self.spaceNeedsRefresh = space.id.id
                    space.isPublic = false
                    self.objectWillChange.send()
                }.cancel()
            }
        }
    }

    func addSoloACLs(space: Space, emails: [String], acl: SpaceACLLevel, note: String) {
        DispatchQueue.main.async {
            let request = AddSoloACLsRequest(
                spaceID: space.id.id, emails: emails, acl: acl, note: note)
            request.$state.sink { state in
                self.spaceNeedsRefresh = space.id.id
                space.isShared = true
                self.objectWillChange.send()
            }.cancel()
        }
    }

    func updateSpaceHeader(
        space: Space, title: String,
        description: String? = nil, thumbnail: String? = nil
    ) {
        DispatchQueue.main.async {
            let request = UpdateSpaceRequest(
                spaceID: space.id.id, title: title,
                description: description, thumbnail: thumbnail)
            request.$state.sink { state in
                self.spaceNeedsRefresh = space.id.id
                space.name = title
                space.description = description
                space.thumbnail = thumbnail
                self.objectWillChange.send()
            }.cancel()
        }
    }

    func deleteGeneratorFromSpace(spaceID: String, generatorID: String) {
        DispatchQueue.main.async {
            let request = DeleteGeneratorRequest(spaceID: spaceID, generatorID: generatorID)
            request.$state.sink { state in
                self.spaceNeedsRefresh = spaceID
            }.cancel()
        }
    }

    func removeSpace(spaceID: String, isOwner: Bool) {

        if isOwner {
            let request = DeleteSpaceRequest(spaceID: spaceID)
            editingSubscription = request.$state.sink { state in
                switch state {
                case .success:
                    self.editingSubscription?.cancel()
                    self.detailedSpace = nil
                    self.manager.refresh()
                case .failure:
                    self.editingSubscription?.cancel()
                case .initial:
                    Logger.browser.info("Waiting for success or failure")
                }
            }
        } else {
            let request = UnfollowSpaceRequest(spaceID: spaceID)
            editingSubscription = request.$state.sink { state in
                switch state {
                case .success:
                    self.editingSubscription?.cancel()
                    self.detailedSpace = nil
                    self.manager.refresh()
                case .failure:
                    self.editingSubscription?.cancel()
                case .initial:
                    Logger.browser.info("Waiting for success or failure")
                }
            }
        }
    }

    func recommendedSpaceSelected(details: SpaceCardDetails) {
        let spaceID = details.id
        let space = SpaceStore.suggested.allSpaces.first(where: {
            $0.id.id == spaceID
        })
        SpaceStore.onRecommendedSpaceSelected(space: space!)
        SpaceStore.shared.objectWillChange.send()
        recommendationSubscription = objectWillChange.sink {
            let newDetails = self.allDetails.first(where: {
                $0.id == spaceID
            })
            DispatchQueue.main.async {
                newDetails?.isShowingDetails = true
                self.spaceNeedsRefresh = spaceID
                self.recommendationSubscription?.cancel()
            }
        }
    }

    func promoCard() -> PromoCardType {
        return .blackFridayNotifyPromo(
            action: {
                ClientLogger.shared.logCounter(
                    .BlackFridayNotifyPromo)
                NotificationPermissionHelper.shared.requestPermissionIfNeeded(
                    completion: { authorized in
                        Defaults[.seenBlackFridayNotifyPromo] = true
                    },
                    callSite: .blackFriday
                )
            },
            onClose: {
                ClientLogger.shared.logCounter(
                    .CloseBlackFridayNotifyPromo)
                Defaults[.seenBlackFridayNotifyPromo] = true
            })
    }
}

class SiteCardModel: CardModel {
    typealias Manager = SiteFetcher
    typealias Details = SiteCardDetails

    @Published var manager = SiteFetcher()
    @Published var allDetails: [SiteCardDetails] = [] {
        didSet {
            allDetailsWithExclusionList = allDetails
        }
    }
    @Published var allDetailsWithExclusionList: [SiteCardDetails] = []
    var anyCancellable: AnyCancellable? = nil
    let tabManager: TabManager

    init(urls: [URL], tabManager: TabManager) {
        self.tabManager = tabManager

        self.allDetails = urls.reduce(into: []) {
            $0.append(SiteCardDetails(url: $1, fetcher: manager, tabManager: tabManager))
        }
        self.anyCancellable = manager.objectWillChange.sink { [weak self] (_) in
            self?.objectWillChange.send()
        }
    }

    func refresh(urls: [URL]) {
        self.allDetails = urls.reduce(into: []) {
            $0.append(SiteCardDetails(url: $1, fetcher: manager, tabManager: tabManager))
        }
    }

    func onDataUpdated() {}
}

class TabGroupCardModel: CardModel {
    var onViewUpdate: () -> Void = {}
    var manager: TabGroupManager
    var anyCancellable: AnyCancellable? = nil
    private var detailsSubscriptions: Set<AnyCancellable> = Set()
    private var screenshotsSubscriptions: Set<AnyCancellable> = Set()

    private var stateNeedsRefresh = false

    var allDetails: [TabGroupCardDetails] = [] {
        didSet {
            allDetailsWithExclusionList = allDetails
        }
    }
    @Published var allDetailsWithExclusionList: [TabGroupCardDetails] = []
    @Published var representativeTabs: [Tab] = []
    @Default(.tabGroupExpanded) private var tabGroupExpanded: Set<String>
    private var tabGroupExpandedSubscriptions: Set<AnyCancellable> = Set()

    init(manager: TabGroupManager) {
        self.manager = manager

        onDataUpdated()
        setupDetailsListener()

        _tabGroupExpanded.publisher.sink {
            [unowned self] _ in
            self.objectWillChange.send()
        }.store(in: &self.tabGroupExpandedSubscriptions)

        self.anyCancellable = self.manager.objectWillChange.sink {
            guard manager.tabManager.didRestoreAllTabs else {
                return
            }

            self.setupDetailsListener()
        }
    }

    func onDataUpdated() {
        onViewUpdate()
        representativeTabs = manager.getAll()
            .reduce(into: [Tab]()) { $0.append($1.children.first!) }
        allDetails = manager.getAll()
            .map {
                TabGroupCardDetails(
                    tabGroup: $0,
                    tabGroupManager: manager)
            }
        objectWillChange.send()
    }

    func setupDetailsListener() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.allDetails = self.manager.getAll().map {
                TabGroupCardDetails(tabGroup: $0, tabGroupManager: self.manager)
            }
            self.manager.cleanUpTabGroupNames()
            self.representativeTabs = self.manager.getAll()
                .reduce(into: [Tab]()) { $0.append($1.children.first!) }
        }
    }
}

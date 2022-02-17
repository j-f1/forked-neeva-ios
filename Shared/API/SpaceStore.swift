// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Apollo
import Combine
import CoreSpotlight
import Foundation

public struct SpaceID: Hashable, Identifiable {
    let value: String

    public var id: String { value }
}

public struct SpaceCommentData {
    public typealias Profile = GetSpacesDataQuery.Data.GetSpace.Space.Space.Comment.Profile
    public let id: String
    public let profile: Profile
    public let createdTs: String
    public let comment: String

    public init(id: String, profile: Profile, createdTs: String, comment: String) {
        self.id = id
        self.profile = profile
        self.createdTs = createdTs
        self.comment = comment
    }

    public var formattedRelativeTime: String {
        let originalDateFormatter = DateFormatter()
        originalDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        originalDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let convertedDate = originalDateFormatter.date(from: createdTs) else {
            return ""
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeDate = formatter.localizedString(for: convertedDate, relativeTo: Date())
        return relativeDate
    }
}

public struct SpaceGeneratorData {
    public var id: String
    public var params: [String: String]

    public var query: String? {
        params["query"]
    }

    static func params(from paramsString: String) -> [String: String]? {
        guard let data = paramsString.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
    }
}

public class Space: Hashable, Identifiable {
    public typealias Acl = ListSpacesQuery.Data.ListSpace.Space.Space.Acl
    public typealias Notification = ListSpacesQuery.Data.ListSpace.Space.Space.Notification

    public static let CSItemDomainIdentifier: String = "co.neeva.app.ios.browser.space"
    public static let CSItemContentType: UTType = .urlBookmarkData

    public var id: SpaceID
    public var name: String
    public var description: String?
    public var thumbnail: String?
    public var followers: Int?
    public var views: Int?
    public let lastModifiedTs: String
    public let resultCount: Int
    public let isDefaultSpace: Bool
    public var isShared: Bool
    public var isPublic: Bool
    public var userACL: SpaceACLLevel
    public let acls: [Acl]
    public let notifications: [Notification]?
    public var isDigest = false

    init(
        id: SpaceID, name: String, description: String? = nil, followers: Int? = nil,
        views: Int? = nil, lastModifiedTs: String, thumbnail: String?,
        resultCount: Int, isDefaultSpace: Bool, isShared: Bool, isPublic: Bool,
        userACL: SpaceACLLevel, acls: [Acl] = [], notifications: [Notification]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.followers = followers
        self.views = views
        self.lastModifiedTs = lastModifiedTs
        self.thumbnail = thumbnail
        self.resultCount = resultCount
        self.isDefaultSpace = isDefaultSpace
        self.isShared = isShared
        self.isPublic = isPublic
        self.userACL = userACL
        self.acls = acls
        self.notifications = notifications
    }

    public var url: URL {
        NeevaConstants.appSpacesURL / id.value
    }

    public var urlWithAddedItem: URL {
        url.withQueryParam("hid", value: contentData?.first?.id ?? "")
    }

    public var contentURLs: Set<URL>?
    public var contentData: [SpaceEntityData]?
    public var comments: [SpaceCommentData]?
    public var generators: [SpaceGeneratorData]?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(lastModifiedTs)
    }
    public static func == (lhs: Space, rhs: Space) -> Bool {
        lhs.id == rhs.id && lhs.lastModifiedTs == rhs.lastModifiedTs
    }

    // Notifications
    public var entityAddedNotifcations: [Notification]? {
        guard let notifications = notifications else {
            return nil
        }

        return notifications.filter {
            return $0.data?.asNotificationSpaceEntitiesAdded?.itemId != nil
        }
    }

    public var hasNotificationUpdates: Bool {
        (entityAddedNotifcations?.count ?? 0) > 0
    }
}

// A store of all spaces data available to the client. Hides details of how the
// data is stored and fetched.
public class SpaceStore: ObservableObject {
    public static var shared = SpaceStore()
    public static var suggested = SpaceStore(
        suggestedID: "c3Z5QSdvOcybtFTY5uboDyvhm4W8mywvEyvCcdtU")

    public static var promotionalSpaceId =
        "-ysvXOiH2HWXsXeN_QaVFzwWEF_ASvtOW_yylJEM"
    public static let dailyDigestID = "spaceDailyDigest"
    public static let dailyDigestSeeMoreID = "\(SpaceStore.dailyDigestID)SeeMore"

    private static var subscription: AnyCancellable? = nil
    private var refreshCompletionHandlers: [() -> Void] = []
    private var suggestedSpaceID: String? = nil

    public init(suggestedID: String? = nil) {
        self.suggestedSpaceID = suggestedID
    }

    public static func createMock(_ spaces: [Space]) -> SpaceStore {
        let mock = SpaceStore()
        mock.allSpaces = spaces
        mock.disableRefresh = true
        return mock
    }

    public enum State {
        case ready
        case refreshing
        case failed(Error)
    }

    /// The current state of the `SpaceStore`.
    @Published public private(set) var state: State = .ready

    /// The current set of spaces.
    @Published public private(set) var allSpaces: [Space] = []
    /// The current set of editable spaces.
    public var editableSpaces: [Space] {
        allSpaces.filter { $0.userACL >= .edit }
    }

    private var disableRefresh = false

    private var urlToSpacesMap: [URL: [Space]] = [:]

    private var queuedRefresh = false
    public private(set) var updatedSpacesFromLastRefresh = [Space]()

    /// Use to query the set of spaces containing the given URL.
    func urlToSpaces(_ url: URL) -> [Space] {
        return urlToSpacesMap[url] ?? []
    }

    /// Use to query if `url` is part of the space specified by `spaceId`
    func urlInSpace(_ url: URL, spaceId: SpaceID) -> Bool {
        return urlToSpaces(url).contains { $0.id == spaceId }
    }

    public func urlInASpace(_ url: URL) -> Bool {
        return !urlToSpaces(url).isEmpty
    }

    /// Call to refresh the SpaceStore's copy of spaces data. Ignored if already refreshing.
    /// - Parameters:
    ///   - force: If true, updates the details in SpaceCardModel.
    public func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        if let completion = completion {
            refreshCompletionHandlers.append(completion)
        }

        if case .refreshing = state {
            return
        }

        if disableRefresh {
            return
        }

        if let _ = suggestedSpaceID {
            fetchSuggestedSpaces()
            return
        }

        state = .refreshing

        SpaceListController.getSpaces { result in
            switch result {
            case .success(let spaces):
                self.onUpdateSpaces(spaces, force: force)
            case .failure(let error):
                self.state = .failed(error)
            }

            for handler in self.refreshCompletionHandlers {
                handler()
            }

            self.refreshCompletionHandlers.removeAll()
        }
    }

    public func refreshSpace(spaceID: String) {
        guard let space = allSpaces.first(where: { $0.id.id == spaceID }),
            let index = allSpaces.firstIndex(where: { $0.id.id == spaceID })
        else {
            return
        }
        if case .refreshing = state {
            queuedRefresh = true
            return
        }
        if disableRefresh { return }
        state = .refreshing

        fetch(spaces: [space])

        let indexSet: IndexSet = [index]
        allSpaces.move(fromOffsets: indexSet, toOffset: 0)
    }

    private func fetchSuggestedSpaces() {
        guard let id = suggestedSpaceID else {
            return
        }

        GraphQLAPI.shared.isAnonymous = true
        allSpaces.append(
            Space(
                id: SpaceID(value: id), name: "", description: nil,
                followers: nil, views: nil, lastModifiedTs: "", thumbnail: nil, resultCount: 1,
                isDefaultSpace: false, isShared: false, isPublic: true, userACL: .publicView,
                acls: [], notifications: []))
        refreshSpace(spaceID: id)
        GraphQLAPI.shared.isAnonymous = false
    }

    public static func onRecommendedSpaceSelected(space: Space) {
        shared.allSpaces.append(space)
        SpacesDataQueryController.getSpacesData(spaceIds: [space.id.id]) { result in
            switch result {
            case .success:
                Logger.browser.info("Space followed")
            case .failure(let error):
                Logger.browser.error(error.localizedDescription)
            }
        }
    }

    public static func openSpace(spaceId: String, completion: @escaping () -> Void) {
        if spaceId == SpaceStore.dailyDigestID {
            shared.refresh {
                shared.addDailyDigestToSpaces()
                completion()
            }
        } else {
            SpacesDataQueryController.getSpacesData(spaceIds: [spaceId]) { result in
                switch result {
                case .success:
                    Logger.browser.info("Space followed")
                    shared.refresh()
                    subscription = SpaceStore.shared.$state.sink {
                        state in
                        if case .ready = state {
                            completion()
                            subscription?.cancel()
                        }
                    }
                case .failure(let error):
                    Logger.browser.error(error.localizedDescription)
                }
            }
        }
    }

    public static func followSpace(spaceId: String, completion: @escaping () -> Void) {
        SpacesDataQueryController.getSpacesData(spaceIds: [spaceId]) { result in
            switch result {
            case .success:
                Logger.browser.info("Space followed")
                completion()
            case .failure(let error):
                Logger.browser.error(error.localizedDescription)
            }
        }
    }

    private func onUpdateSpaces(_ spaces: [SpaceListController.Space], force: Bool = false) {
        let oldSpaceMap: [SpaceID: Space] = Dictionary(
            uniqueKeysWithValues: allSpaces.map { ($0.id, $0) })

        // Clear to avoid holding stale data. Will be rebuilt below.
        urlToSpacesMap = [:]

        var spacesToFetch: [Space] = []

        var allSpaces = [Space]()
        // Build the set of spaces:
        for space in spaces {
            if let pageId = space.pageMetadata?.pageId,
                let space = space.space,
                let name = space.name,
                let lastModifiedTs = space.lastModifiedTs,
                let userAcl = space.userAcl?.acl
            {
                let spaceId = SpaceID(value: pageId)
                let newSpace = Space(
                    id: spaceId,
                    name: name,
                    lastModifiedTs: lastModifiedTs,
                    thumbnail: space.thumbnail ?? nil,
                    resultCount: space.resultCount ?? 0,
                    isDefaultSpace: space.isDefaultSpace ?? false,
                    isShared:
                        !(space.acl?.map(\.userId).filter { $0 != NeevaUserInfo.shared.id }.isEmpty
                        ?? true),
                    isPublic: space.hasPublicAcl ?? false,
                    userACL: userAcl,
                    acls: space.acl ?? [],
                    notifications: space.notifications
                )

                /// Note, we avoid parsing `lastModifiedTs` here and instead just use it as
                /// an opaque identifier. If the value we have stored from last fetch differs
                /// from the current value, then we'll just refetch the URLs for the space.
                /// Otherwise, we can use our cached data.
                if let oldSpace = oldSpaceMap[spaceId],
                    let contentURLs = oldSpace.contentURLs,
                    let contentData = oldSpace.contentData,
                    let comments = oldSpace.comments,
                    let generators = oldSpace.generators,
                    space.lastModifiedTs == oldSpace.lastModifiedTs
                {
                    self.onUpdateSpaceURLs(
                        space: newSpace,
                        description: oldSpace.description,
                        followers: oldSpace.followers,
                        views: oldSpace.views,
                        urls: contentURLs,
                        data: contentData,
                        comments: comments,
                        generators: generators)
                } else {
                    spacesToFetch.append(newSpace)
                }

                allSpaces.append(newSpace)
            }
        }

        // add spaces to CS
        for space in allSpaces {
            let attributes = CSSearchableItemAttributeSet(contentType: Space.CSItemContentType)
            attributes.title = space.name
            attributes.contentDescription = space.description
            let item = CSSearchableItem(
                uniqueIdentifier: space.id.id,
                domainIdentifier: Space.CSItemDomainIdentifier,
                attributeSet: attributes
            )
            // make this pretty
            CSSearchableIndex.default().indexSearchableItems([item]) { error in
                if let error = error {
                    Logger.storage.error("Error: \(error)")
                }
            }
        }

        self.allSpaces = allSpaces

        if spacesToFetch.count > 0 {
            fetch(spaces: spacesToFetch)
        } else {
            self.updatedSpacesFromLastRefresh = force ? allSpaces : []
            self.state = .ready

            addDailyDigestToSpaces()
        }
    }

    private func fetch(spaces spacesToFetch: [Space]) {
        SpacesDataQueryController.getSpacesData(spaceIds: spacesToFetch.map(\.id.value)) {
            result in
            switch result {
            case .success(let spaces):
                for space in spaces {
                    /// Note, we could update the `lastModifiedTs` field here but that's
                    /// likely an unnecessary optimization. The window between now and
                    /// when ListSpaces returned is short, and the downside of having a
                    /// stale `lastModifiedTs` stored in our cache is minor.

                    let containerSpace = spacesToFetch.first { $0.id.value == space.id }!
                    containerSpace.name = space.name
                    self.onUpdateSpaceURLs(
                        space: containerSpace,
                        description: space.description,
                        followers: space.followers,
                        views: space.views,
                        urls: Set(
                            space.entities.filter { $0.url != nil }.reduce(into: [URL]()) {
                                $0.append($1.url!)
                            }),
                        data: space.entities,
                        comments: space.comments,
                        generators: space.generators
                    )
                }

                self.updatedSpacesFromLastRefresh = spacesToFetch
                self.state = .ready
                self.addDailyDigestToSpaces()

                if self.queuedRefresh {
                    self.refresh()
                    self.queuedRefresh = false
                }
            case .failure(let error):
                self.state = .failed(error)
            }
        }
    }

    private func onUpdateSpaceURLs(
        space: Space, description: String?, followers: Int?, views: Int?,
        urls: Set<URL>, data: [SpaceEntityData], comments: [SpaceCommentData],
        generators: [SpaceGeneratorData]
    ) {
        space.contentURLs = urls
        space.contentData = data
        space.comments = comments
        space.generators = generators
        space.description = description
        space.followers = followers
        space.views = views
        for url in urls {
            var spaces = urlToSpacesMap[url] ?? []
            spaces.append(space)
            urlToSpacesMap[url] = spaces
        }
    }

    // MARK: - Daily Digest
    public func addDailyDigestToSpaces() {
        self.allSpaces.removeAll(where: { $0.isDigest })
        self.allSpaces.insert(createSpaceDailyDigest(with: allSpaces), at: 0)
    }

    private func createSpaceDailyDigest(with spaces: [Space]) -> Space {
        let spacesWithNotifications: [Space] = spaces.compactMap {
            if $0.hasNotificationUpdates {
                return $0
            } else {
                return nil
            }
        }

        let spaceDailyDigest = Space.empty()
        spaceDailyDigest.id = .init(value: SpaceStore.dailyDigestID)

        spaceDailyDigest.contentData = []
        spaceDailyDigest.userACL = .publicView
        spaceDailyDigest.isDigest = true

        var numberOfItemsUpdated = 0

        for space in spacesWithNotifications {
            if let content = space.contentData, let notifications = space.entityAddedNotifcations {
                let headerData = SpaceEntityData(
                    id: space.id.id,
                    url: nil,
                    title: space.name,
                    snippet: nil,
                    thumbnail: nil,
                    previewEntity: .spaceLink(space.id))
                spaceDailyDigest.contentData?.append(headerData)

                var extraItemCount = 0

                for (index, notification) in notifications.enumerated() {
                    guard
                        let notification = notification.data?.asNotificationSpaceEntitiesAdded,
                        let data = content.first(where: {
                            $0.id == notification.itemId
                        })
                    else {
                        continue
                    }

                    if data.url != nil {
                        numberOfItemsUpdated += 1

                        if index < 2 {
                            spaceDailyDigest.contentData?.append(data)
                        } else {
                            extraItemCount += 1
                        }
                    }
                }

                if extraItemCount > 0 {
                    let seeMore = SpaceEntityData(
                        id: .init(SpaceStore.dailyDigestSeeMoreID),
                        url: space.url,
                        title: "\(extraItemCount) more",
                        snippet: nil,
                        thumbnail: nil,
                        previewEntity: .spaceLink(space.id))
                    spaceDailyDigest.contentData?.append(seeMore)
                }
            }
        }

        spaceDailyDigest.name =
            "Daily Digest\(numberOfItemsUpdated > 0 ? " (\(numberOfItemsUpdated))" : "")"

        // (Evan) Commenting this out as we're testing hiding the description.
        /* spaceDailyDigest.description = createDailyDigestDescription(
            spaces: spacesWithNotifications, numberOfChanges: numberOfItemsUpdated) */

        return spaceDailyDigest
    }

    private func createDailyDigestDescription(spaces: [Space], numberOfChanges: Int) -> String {
        var description = ""

        guard spaces.count > 0 else {
            return "No spaces have been updated"
        }

        let numberOfSpaces = spaces.count

        // 1 Space / 2 Spaces
        description += "\(numberOfSpaces) Space\(numberOfSpaces > 1 ? "s" : "")"

        // was / were updated with 1 item / 2 items total
        description +=
            " \(spaces.count > 1 ? "were" : "was") updated with \(numberOfChanges) \(numberOfChanges > 1 ? "items" : "item") total"

        return description
    }
}

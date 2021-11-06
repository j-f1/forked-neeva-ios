// Copyright Neeva. All rights reserved.

import Combine
import Shared
import Storage
import SwiftUI

enum ContentUIType: Equatable {
    case webPage(WKWebView)
    case zeroQuery
    case suggestions
    case blank
}

enum ContentUIVisibilityEvent {
    case showZeroQuery(isIncognito: Bool, isLazyTab: Bool, ZeroQueryOpenedLocation?)
    case hideZeroQuery
    case showSuggestions
    case hideSuggestions
}

class TabContentHostModel: ObservableObject {
    /// Holds the current webpage's WebView, so that when the state changes to be other content, we don't lose it.
    @Published var webContainerType: ContentUIType {
        didSet {
            switch currentContentUI {
            case .webPage:
                currentContentUI = webContainerType
            case .blank:
                currentContentUI = webContainerType
            default:
                return
            }
        }
    }
    /// Current content UI that is showing
    @Published var currentContentUI: ContentUIType

    @Published var recipeModel: RecipeViewModel

    var subscription: AnyCancellable? = nil

    init(bvc: BrowserViewController) {
        let tabManager = bvc.tabManager
        let webView = tabManager.selectedTab?.webView
        let type = webView.map(ContentUIType.webPage) ?? .blank
        self.webContainerType = type
        self.currentContentUI = type
        self.recipeModel = RecipeViewModel(tabManager: tabManager)
        self.subscription = tabManager.selectedTabPublisher.sink { [unowned self] tab in
            guard let webView = tab?.webView else {
                webContainerType = .blank
                return
            }
            webContainerType = .webPage(webView)

            if NeevaFeatureFlags[.recipeCheatsheet] && !tabManager.isIncognito {
                if let url = webView.url {
                    self.recipeModel.updateContentWithURL(url: url)
                    bvc.chromeModel.currentCheatsheetFaviconURL =
                        tabManager.selectedTab?.favicon?.url
                    bvc.chromeModel.currentCheatsheetURL = tabManager.selectedTab?.url
                }
            }
        }
    }
}

class TabContentHost: IncognitoAwareHostingController<TabContentHost.Content> {
    let zeroQueryModel: ZeroQueryModel
    let model: TabContentHostModel
    let tabCardModel: TabCardModel

    struct Content: View {
        @ObservedObject var model: TabContentHostModel
        let bvc: BrowserViewController
        let zeroQueryModel: ZeroQueryModel
        let suggestionModel: SuggestionModel
        let suggestedSitesViewModel: SuggestedSitesViewModel = SuggestedSitesViewModel(sites: [])
        let suggestedSearchesModel: SuggestedSearchesModel =
            SuggestedSearchesModel(suggestedQueries: [])
        let spaceContentSheetModel: SpaceContentSheetModel?

        var body: some View {
            ZStack {
                switch model.currentContentUI {
                case .webPage(let currentWebView):
                    ZStack {
                        WebViewContainer(webView: currentWebView)
                            .ignoresSafeArea()

                        if FeatureFlag[.cardStrip] {
                            GeometryReader { geo in
                                VStack {
                                    Spacer()
                                    CardStripContent(bvc: bvc, width: geo.size.width)
                                }
                            }
                        }
                        if FeatureFlag[.spaceComments] {
                            SpaceContentSheet(
                                model: spaceContentSheetModel!,
                                scrollingController: bvc.scrollController
                            )
                            .environment(
                                \.onOpenURLForSpace, bvc.tabManager.createOrSwitchToTabForSpace)
                        }
                        if NeevaFeatureFlags[.recipeCheatsheet] && !bvc.tabManager.isIncognito {
                            GeometryReader { geo in
                                VStack {
                                    Spacer()
                                    RecipeCheatsheetStripView(
                                        tabManager: bvc.tabManager,
                                        recipeModel: model.recipeModel,
                                        scrollingController: bvc.scrollController,
                                        height: geo.size.height,
                                        chromeModel: bvc.chromeModel
                                    )
                                    .environment(\.onOpenURL) { url in
                                        let bvc = zeroQueryModel.bvc
                                        bvc.tabManager.createOrSwitchToTab(for: url)
                                    }
                                }
                            }
                        }
                    }
                case .zeroQuery:
                    ZeroQueryContent(model: zeroQueryModel)
                        .environmentObject(suggestedSitesViewModel)
                        .environmentObject(suggestedSearchesModel)
                case .suggestions:
                    SuggestionsContent(suggestionModel: suggestionModel)
                        .environment(\.onOpenURL) { url in
                            let bvc = zeroQueryModel.bvc
                            guard let tab = bvc.tabManager.selectedTab else { return }
                            bvc.finishEditingAndSubmit(
                                url, visitType: VisitType.typed, forTab: tab)
                        }.environment(\.setSearchInput) { suggestion in
                            suggestionModel.queryModel.value = suggestion
                        }.environment(\.onSigninOrJoinNeeva) {
                            ClientLogger.shared.logCounter(
                                .SuggestionErrorSigninOrJoinNeeva,
                                attributes: EnvironmentHelper.shared.getFirstRunAttributes())
                            let bvc = zeroQueryModel.bvc
                            bvc.chromeModel.setEditingLocation(to: false)
                            bvc.presentIntroViewController(
                                true,
                                onDismiss: {
                                    bvc.hideCardGrid(withAnimation: true)
                                }
                            )
                        }
                case .blank:
                    ZeroQueryContent(model: zeroQueryModel)
                        .environmentObject(suggestedSitesViewModel)
                        .environmentObject(suggestedSearchesModel)
                }
            }.useEffect(deps: model.currentContentUI) { _ in
                zeroQueryModel.profile.panelDataObservers.activityStream.refreshIfNeeded(
                    forceTopSites: true)
                TopSitesHandler.getTopSites(
                    profile: zeroQueryModel.profile
                ).uponQueue(.main) { result in
                    self.suggestedSitesViewModel.sites = Array(result.prefix(7))
                }
                self.suggestedSearchesModel.reload(from: zeroQueryModel.profile)
            }
        }
    }

    init(bvc: BrowserViewController) {
        let tabManager = bvc.tabManager
        let model = TabContentHostModel(bvc: bvc)
        let zeroQueryModel = bvc.zeroQueryModel
        let suggestionModel = bvc.suggestionModel

        self.model = model
        self.zeroQueryModel = bvc.zeroQueryModel

        let tabCardModel = TabCardModel(
            manager: tabManager, groupManager: TabGroupManager(tabManager: tabManager))
        self.tabCardModel = tabCardModel

        super.init(isIncognito: tabManager.isIncognito) {
            Content(
                model: model,
                bvc: bvc,
                zeroQueryModel: zeroQueryModel,
                suggestionModel: suggestionModel,
                spaceContentSheetModel: FeatureFlag[.spaceComments]
                    ? SpaceContentSheetModel(
                        tabManager: bvc.tabManager,
                        spaceModel: bvc.cardGridViewController.rootView.spaceCardModel) : nil)
        }

        suggestionModel.getKeyboardHeight = {
            if let view = self.view,
                let currentState = KeyboardHelper.defaultHelper.currentState
            {
                // Minus extra padding which is calculated in landscape mode
                return currentState.intersectionHeightForView(view) - (UIDevice.current.orientation.isLandscape ? 16 : 0)
            } else {
                return 0
            }
        }
    }

    @objc required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult public func promoteToRealTabIfNecessary(
        url: URL, tabManager: TabManager, selectedTabIsNil: Bool = false
    ) -> Bool {
        let result = zeroQueryModel.promoteToRealTabIfNecessary(url: url, tabManager: tabManager)
        if result {
            updateContent(.hideZeroQuery)
        }

        return selectedTabIsNil || result
    }

    func updateContent(_ event: ContentUIVisibilityEvent) {
        switch event {
        case .showZeroQuery(let isIncognito, let isLazyTab, let openedFrom):
            model.currentContentUI = .zeroQuery
            zeroQueryModel.isPrivate = isIncognito
            zeroQueryModel.isLazyTab = isLazyTab
            zeroQueryModel.openedFrom = openedFrom
        case .showSuggestions:
            if case .zeroQuery = model.currentContentUI {
                model.currentContentUI = .suggestions
            }
        case .hideSuggestions:
            if case .suggestions = model.currentContentUI {
                model.currentContentUI = .zeroQuery
                zeroQueryModel.targetTab = .defaultValue
            }
        case .hideZeroQuery:
            model.currentContentUI = model.webContainerType
            self.zeroQueryModel.reset(bvc: nil)
        }
    }
}
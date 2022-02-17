// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Defaults
import Shared
import SwiftUI

enum ToolbarContentView {
    case regularContent
    case recipeContent
}

class TabChromeModel: ObservableObject {
    @Published var canGoBack: Bool

    var canReturnToSuggestions: Bool {
        guard let selectedTab = topBarDelegate?.tabManager.selectedTab,
            let currentItem = selectedTab.webView?.backForwardList.currentItem
        else {
            return false
        }

        return selectedTab.queryForNavigation.findQueryFor(navigation: currentItem) != nil
    }

    @Published var canGoForward: Bool
    @Published var urlInSpace: Bool = false

    /// True when the toolbar is inline with the location view
    /// (when in landscape or on iPad)
    @Published var inlineToolbar: Bool

    @Published var isPage: Bool

    /// True when user has clicked education on SRP and is now not on an SRP
    @Published var showTryCheatsheetPopover: Bool = false
    private var publishedTabObserver: AnyCancellable?
    private var tryCheatsheetPopoverObserver: AnyCancellable?

    var showTopCardStrip: Bool {
        FeatureFlag[.cardStrip] && FeatureFlag[.topCardStrip] && inlineToolbar
            && !isEditingLocation
    }

    var appActiveRefreshSubscription: AnyCancellable? = nil
    private var subscriptions: Set<AnyCancellable> = []
    weak var topBarDelegate: TopBarDelegate? {
        didSet {
            $isEditingLocation
                .withPrevious()
                .sink { [weak topBarDelegate] change in
                    switch change {
                    case (false, true):
                        topBarDelegate?.urlBarDidEnterOverlayMode()
                    case (true, false):
                        topBarDelegate?.urlBarDidLeaveOverlayMode()
                    default: break
                    }
                }
                .store(in: &subscriptions)
            $isEditingLocation
                .combineLatest(topBarDelegate!.searchQueryModel.$value)
                .withPrevious()
                .sink { [weak topBarDelegate] (prev, current) in
                    let (prevEditing, _) = prev
                    let (isEditing, query) = current
                    if let delegate = topBarDelegate, (prevEditing, isEditing) == (true, true) {
                        if query.isEmpty {
                            delegate.tabContainerModel.updateContent(.hideSuggestions)
                        } else {
                            delegate.tabContainerModel.updateContent(.showSuggestions)
                        }
                    }
                }
                .store(in: &subscriptions)
            setupTryCheatsheetPopoverObserver()
        }
    }
    weak var toolbarDelegate: ToolbarDelegate?

    enum ReloadButtonState: String {
        case reload = "Reload"
        case stop = "Stop"
    }
    var reloadButton: ReloadButtonState {
        estimatedProgress == 1 || estimatedProgress == nil ? .reload : .stop
    }
    @Published var estimatedProgress: Double?

    @Published private(set) var isEditingLocation = false

    @Published var showNeevaMenuTourPrompt = false

    @Published var toolBarContentView: ToolbarContentView = .regularContent

    @Published var currentCheatsheetURL: URL? = nil

    @Published var currentCheatsheetFaviconURL: URL? = nil

    private var inlineToolbarHeight: CGFloat {
        return UIConstants.TopToolbarHeightWithToolbarButtonsShowing
            + (showTopCardStrip ? CardControllerUX.Height : 0)
    }

    private var portraitHeight: CGFloat {
        return UIConstants.PortraitToolbarHeight
            + (showTopCardStrip ? CardControllerUX.Height : 0)
    }

    var topBarHeight: CGFloat {
        return inlineToolbar ? inlineToolbarHeight : portraitHeight
    }

    @Published var keyboardShowing = false
    @Published var bottomBarHeight: CGFloat = 0

    init(
        canGoBack: Bool = false, canGoForward: Bool = false, isPage: Bool = false,
        inlineToolbar: Bool = false, estimatedProgress: Double? = nil
    ) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isPage = isPage
        self.inlineToolbar = inlineToolbar
        self.estimatedProgress = estimatedProgress
    }

    /// Calls the address bar to be selected and enter editing mode
    func triggerOverlay() {
        isEditingLocation = true
    }

    func setEditingLocation(to value: Bool) {
        if value {
            toolBarContentView = .regularContent
        }

        withAnimation(TabLocationViewUX.animation) {
            isEditingLocation = value
        }
    }

    func hideZeroQuery() {
        SceneDelegate.getBVC(with: topBarDelegate?.tabManager.scene).hideZeroQuery()
    }

    func setupTryCheatsheetPopoverObserver() {
        publishedTabObserver?.cancel()
        tryCheatsheetPopoverObserver?.cancel()

        guard let tabManager = topBarDelegate?.tabManager,
            let tabContainerModel = topBarDelegate?.tabContainerModel
        else { return }

        publishedTabObserver = tabManager.selectedTabPublisher
            .sink { [weak self] tab in
                self?.tryCheatsheetPopoverObserver?.cancel()
                guard let tab = tab else { return }
                self?.tryCheatsheetPopoverObserver = Publishers.CombineLatest3(
                    Defaults.publisher(.showTryCheatsheetPopover),
                    tabContainerModel.recipeModel.$recipe,
                    tab.$url
                )
                .map { showPopover, recipe, url -> Bool in
                    // extra check in case the query flag changed between launches
                    guard NeevaFeatureFlags[.cheatsheetQuery], let url = url else { return false }
                    // if recipe cheatsheet would've been shown, show popover
                    if !recipe.title.isEmpty,
                        !Defaults[.seenTryCheatsheetPopoverOnRecipe],
                        RecipeViewModel.isRecipeAllowed(url: url)
                    {
                        return true
                    }
                    // else show popover if seen SRP intro screen
                    if showPopover.newValue,
                        // cheatsheet is not used on NeevaDomain
                        !NeevaConstants.isInNeevaDomain(url),
                        // avoid flashing the popover when app launches
                        !(url.scheme == InternalURL.scheme)
                    {
                        return true
                    }
                    return false
                }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    self?.showTryCheatsheetPopover = $0
                    // switching tab right after setting the bool sometimes does not trigger a UI change
                    self?.objectWillChange.send()
                }
            }
    }

    func clearCheatsheetPopoverFlags() {
        guard NeevaFeatureFlags[.cheatsheetQuery] else { return }
        Defaults[.showTryCheatsheetPopover] = false
        if let recipeModel = topBarDelegate?.tabContainerModel.recipeModel,
            !recipeModel.recipe.title.isEmpty
        {
            Defaults[.seenTryCheatsheetPopoverOnRecipe] = true
        }
    }
}

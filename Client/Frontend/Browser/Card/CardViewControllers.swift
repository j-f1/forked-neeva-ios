// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Shared
import SnapKit
import SwiftUI

public enum CardControllerUX {
    static let BottomPadding: CGFloat = 50
    static let Height: CGFloat = 75
    static let HandleWidth: CGFloat = 50
}

class CardGridViewController: UIHostingController<CardGridViewController.Content> {
    struct Content: View {
        let browserModel: BrowserModel
        let gridModel: GridModel
        let toolbarModel: SwitcherToolbarModel
        let web3Model: Web3Model
        let shareURL: (URL, UIView) -> Void

        var body: some View {
            CardGrid()
                .environmentObject(browserModel)
                .environmentObject(toolbarModel)
                .environmentObject(gridModel.tabCardModel)
                .environmentObject(gridModel.spaceCardModel)
                .environmentObject(gridModel.tabGroupCardModel)
                .environmentObject(gridModel)
                .environmentObject(web3Model)
                .environment(
                    \.onOpenURL, { gridModel.tabCardModel.manager.createOrSwitchToTab(for: $0) }
                )
                .environment(
                    \.onOpenURLForSpace,
                    {
                        gridModel.tabCardModel.manager.createOrSwitchToTabForSpace(
                            for: $0, spaceID: $1)
                    }
                )
                .environment(\.shareURL, shareURL)
        }
    }

    var leadingConstraint: Constraint? = nil
    let gridModel: GridModel
    let toolbarModel: SwitcherToolbarModel

    private var subscription: AnyCancellable?

    init(
        tabManager: TabManager, toolbarModel: SwitcherToolbarModel, web3Model: Web3Model,
        gridModel: GridModel, browserModel: BrowserModel, shareURL: @escaping (URL, UIView) -> Void
    ) {
        self.gridModel = gridModel
        self.toolbarModel = toolbarModel
        super.init(
            rootView: Content(
                browserModel: browserModel,
                gridModel: gridModel,
                toolbarModel: toolbarModel,
                web3Model: web3Model,
                shareURL: shareURL
            )
        )

        subscription = browserModel.$showContent.sink { [unowned self] isHidden in
            view.isHidden = isHidden
            view.isUserInteractionEnabled = !isHidden
            if !isHidden {
                parent?.view.bringSubviewToFront(view)
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
    }
}

struct CardStripContent: View {
    let tabCardModel: TabCardModel
    let spaceCardModel: SpaceCardModel
    let sitesCardModel: SiteCardModel
    let gridModel: GridModel
    @ObservedObject var cardStripModel: CardStripModel

    var width: CGFloat

    var body: some View {
        CardStripView()
            .environmentObject(tabCardModel)
            .environmentObject(spaceCardModel)
            .environmentObject(sitesCardModel)
            .environmentObject(cardStripModel)
            .environmentObject(gridModel)
            .offset(x: !cardStripModel.isVisible ? 0 : width - 50)
            .frame(height: CardControllerUX.Height)
    }

    init(bvc: BrowserViewController, width: CGFloat) {
        let tabManager = bvc.tabManager
        let tabGroupManager = bvc.tabGroupManager

        self.tabCardModel = TabCardModel(
            manager: tabManager, groupManager: tabGroupManager)
        self.spaceCardModel = SpaceCardModel()
        self.sitesCardModel = SiteCardModel(urls: [], tabManager: tabManager)
        self.cardStripModel = CardStripModel()
        self.gridModel = bvc.gridModel
        self.width = width
    }
}

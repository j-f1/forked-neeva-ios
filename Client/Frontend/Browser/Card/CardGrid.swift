// Copyright Neeva. All rights reserved.

import Shared
import SwiftUI

enum SwitcherViews: String, CaseIterable {
    case tabs = "Tabs"
    case spaces = "Spaces"
}

enum CardGridUX {
    static let PickerPadding: CGFloat = 20
    static let PickerHeight: CGFloat = UIConstants.TopToolbarHeight
    static let GridSpacing: CGFloat = 20
    static let YStaticOffset: CGFloat = GridSpacing
}

struct CardGrid: View {
    @EnvironmentObject var tabModel: TabCardModel
    @EnvironmentObject var tabGroupModel: TabGroupCardModel
    @EnvironmentObject var gridModel: GridModel

    @State private var switcherState: SwitcherViews = .tabs
    @State private var cardSize: CGFloat = CardUX.DefaultCardSize
    @State private var columnCount = 2
    @State private var geom: (size: CGSize, safeAreaInsets: EdgeInsets)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var topToolbar: Bool {
        verticalSizeClass == .compact || horizontalSizeClass == .regular
    }

    var indexInsideTabGroupModel: Int? {
        guard FeatureFlag[.groupsInSwitcher] else {
            return nil
        }

        let selectedTab = tabModel.manager.selectedTab!
        return tabGroupModel.allDetails
            .firstIndex(where: { $0.id == selectedTab.rootUUID })
    }

    var indexInsideTabModel: Int? {
        if FeatureFlag[.groupsInSwitcher] {
            return tabModel.allDetailsWithExclusionList.firstIndex(where: \.isSelected)
        } else {
            return tabModel.allDetails.firstIndex(where: \.isSelected)
        }
    }

    var indexInGrid: Int {
        indexInsideTabGroupModel
            ?? (FeatureFlag[.groupsInSwitcher] ? tabGroupModel.allDetails.count : 0)
            + indexInsideTabModel!
    }

    var selectedCardDetails: TabCardDetails? {
        if FeatureFlag[.groupsInSwitcher] {
            return tabModel.allDetailsWithExclusionList.first(where: \.isSelected)
                ?? tabGroupModel.allDetails
                .compactMap { $0.allDetails.first(where: \.isSelected) }
                .first
        } else {
            return tabModel.allDetails.first(where: \.isSelected)
        }
    }

    var row: CGFloat {
        floor(CGFloat(indexInGrid) / columnCount)
    }

    @ViewBuilder var transitionAnimator: some View {
        if gridModel.animationThumbnailState != .hidden || gridModel.isHidden,
            let selectedCardDetails = selectedCardDetails,
            let geom = geom
        {
            CardTransitionAnimator(
                selectedCardDetails: selectedCardDetails,
                cardSize: cardSize,
                offset: CGPoint(
                    x: CardGridUX.GridSpacing
                        + (CardGridUX.GridSpacing + cardSize) * (indexInGrid % columnCount),
                    y: (CardUX.HeaderSize + CardGridUX.GridSpacing + cardSize) * row
                        + CardGridUX.YStaticOffset
                ),
                containerSize: geom.size,
                safeAreaInsets: geom.safeAreaInsets,
                topToolbar: topToolbar
            )
        }
    }

    func updateCardSize(width: CGFloat, isHidden: Bool) {
        if width > 1000 {
            columnCount = 4
        } else {
            switch horizontalSizeClass {
            case .regular:
                columnCount = 3
            default: columnCount = topToolbar ? 3 : 2
            }
        }
        self.cardSize = (width - (columnCount + 1) * CardGridUX.GridSpacing) / columnCount
    }

    var body: some View {
        GeometryReader { geom in
            VStack(spacing: 0) {
                if topToolbar {
                    SwitcherToolbarView(top: true)
                }
                VStack(spacing: 0) {
                    if FeatureFlag[.nativeSpaces] {
                        GridPicker(switcherState: $switcherState)
                    }
                    CardsContainer(
                        switcherState: $switcherState,
                        columns: Array(
                            repeating:
                                GridItem(
                                    .fixed(cardSize),
                                    spacing: CardGridUX.GridSpacing),
                            count: columnCount)
                    )
                    .environment(\.cardSize, cardSize)
                    Spacer(minLength: 0)
                }
                .background(Color(UIColor.TabTray.background).ignoresSafeArea())
                if !topToolbar {
                    SwitcherToolbarView(top: false)
                }
            }
            .useEffect(deps: geom.size.width, gridModel.isHidden, perform: updateCardSize)
            .useEffect(deps: geom.size, geom.safeAreaInsets) { self.geom = ($0, $1) }
        }
        .overlay(transitionAnimator, alignment: .top)
        .ignoresSafeArea(.keyboard)
        .accessibilityAction(.escape) {
            gridModel.animationThumbnailState = .visibleForTrayHidden
        }
    }
}

struct GridPicker: View {
    @Binding var switcherState: SwitcherViews

    var body: some View {
        Picker("", selection: $switcherState) {
            ForEach(SwitcherViews.allCases, id: \.rawValue) { view in
                Text(view.rawValue).tag(view)
            }
        }.pickerStyle(SegmentedPickerStyle())
            .padding(CardGridUX.PickerPadding)
            .frame(height: CardGridUX.PickerHeight)
            .background(Color.background)
    }
}

struct ScrollViewOffsetPreferenceKey: PreferenceKey {
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }

    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
}

// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Shared
import SwiftUI

enum SingleLevelTabCardsViewUX {
    static let TabGroupCarouselTitleSize: CGFloat = 22
    static let TabGroupCarouselTitleSpacing: CGFloat = 16
    static let TabGroupCarouselTopPadding: CGFloat = 16
    static let TabGroupCarouselBottomPadding: CGFloat = 8
    static let TabGroupCarouselTabSpacing: CGFloat = 12
}

struct SingleLevelTabCardsView: View {
    @EnvironmentObject var tabModel: TabCardModel
    @EnvironmentObject var tabGroupModel: TabGroupCardModel
    @Environment(\.columns) private var columns

    let containerGeometry: GeometryProxy
    let incognito: Bool

    var body: some View {
        ForEach(
            tabModel.buildRows(
                incognito: incognito, tabGroupModel: tabGroupModel, maxCols: columns.count)
        ) { row in
            HStack(spacing: CardGridUX.GridSpacing) {
                ForEach(row.cells) { details in
                    switch details {
                    case .tabGroupInline(let groupDetails):
                        CollapsedCardGroupView(
                            groupDetails: groupDetails, containerGeometry: containerGeometry,
                            nextToCells: row.multipleCellTypes
                        )
                        .padding(.horizontal, -CardGridUX.GridSpacing)
                        .padding(.bottom, CardGridUX.GridSpacing)
                        .zIndex(groupDetails.allDetails.contains(where: \.isSelected) ? 1 : 0)
                    case .tabGroupGridRow(let groupDetails, let range):
                        ExpandedCardGroupRowView(
                            groupDetails: groupDetails, containerGeometry: containerGeometry,
                            range: range, nextToCells: false
                        )
                        .padding(.horizontal, -CardGridUX.GridSpacing)
                        .padding(
                            .bottom,
                            lastRowTabGroup(range, groupDetails) ? CardGridUX.GridSpacing : 0)
                    case .tab(let tabDetails):
                        FittedCard(details: tabDetails)
                            .modifier(
                                CardTransitionModifier(
                                    details: tabDetails, containerGeometry: containerGeometry)
                            )
                            .padding(.bottom, CardGridUX.GridSpacing)
                    }
                }
            }
            .padding(.horizontal, CardGridUX.GridSpacing)
            .zIndex(row.cells.contains(where: \.isSelected) ? 1 : 0)
        }
    }

    func lastRowTabGroup(_ rowInfo: Range<Int>, _ groupDetails: TabGroupCardDetails) -> Bool {
        return rowInfo.last == groupDetails.allDetails.count - 1
    }
}

// Copyright Neeva. All rights reserved.

import SFSafeSymbols
import Shared
import SwiftUI

struct TabToolbarButton<Content: View>: View {
    let label: Content
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Spacer(minLength: 0)
            label.tapTargetFrame()
            Spacer(minLength: 0)
        }.accentColor(isEnabled ? .label : .quaternaryLabel)
    }
}

enum TabToolbarButtons {
    struct BackForward: View {
        let weight: Font.Weight
        let onBack: () -> Void
        let onForward: () -> Void
        let onOverflow: () -> Void
        let onLongPress: () -> Void

        @EnvironmentObject private var model: TabChromeModel
        var body: some View {
            Group {
                TabToolbarButton(
                    label: Symbol(
                        .arrowBackward, size: 20, weight: weight,
                        label: .TabToolbarBackAccessibilityLabel), action: onBack
                )
                .disabled(!model.canGoBack)
                .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPress() })
                if FeatureFlag[.overflowMenu] {
                    TabToolbarButton(
                        label: Symbol(
                            .ellipsisCircle, size: 20, weight: weight,
                            label: .TabToolbarMoreAccessibilityLabel),
                        action: onOverflow
                    )
                } else {
                    TabToolbarButton(
                        label: Symbol(
                            .arrowForward, size: 20, weight: weight,
                            label: .TabToolbarForwardAccessibilityLabel), action: onForward
                    )
                    .disabled(!model.canGoForward)
                    .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPress() })
                }
            }
        }
    }

    struct NeevaMenu: View {
        let iconWidth: CGFloat
        let action: () -> Void

        @Environment(\.isIncognito) private var isIncognito

        var body: some View {
            TabToolbarButton(
                label: Image("neevaMenuIcon")
                    .renderingMode(isIncognito ? .template : .original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconWidth)
                    .accessibilityLabel("Neeva Menu"),
                action: action
            )
        }
    }

    struct AddToSpace: View {
        let weight: Font.Weight
        let action: () -> Void

        @Environment(\.isIncognito) private var isIncognito
        @EnvironmentObject private var model: TabChromeModel

        var body: some View {
            TabToolbarButton(
                label: Symbol(.bookmark, size: 20, weight: weight, label: "Add To Space"),
                action: action
            )
            .disabled(isIncognito || !model.isPage)
        }
    }

    struct ShowTabs: View {
        let weight: UIImage.SymbolWeight
        let action: () -> Void
        let buildMenu: () -> UIMenu?

        var body: some View {
            // TODO: when dropping support for iOS 14, change this to a Menu view with a primaryAction
            UIKitButton(action: action) {
                $0.setImage(Symbol.uiImage(.squareOnSquare, size: 20, weight: weight), for: .normal)
                $0.setDynamicMenu(buildMenu)
                $0.accessibilityLabel = "Show Tabs"
            }
        }
    }
}
// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation
import Shared
import SwiftUI

enum OverlaySheetUX {
    /// Number of points you have to drag the top bar to tigger an animation
    /// of the overlay sheet to a new position.
    static let slideThreshold: CGFloat = 100

    /// Duration of slide animations.
    static let animationDuration: Double = 0.2

    /// Opacity of the backdrop when the overlay sheet is done animating open.
    static let backdropMaxOpacity: Double = 0.2

    /// Width of the sheet when in landscape mode.
    static let landscapeModeWidth: CGFloat = 500

    /// Top padding applied to the whole sheet
    static let topPadding: CGFloat = 16

    /// Bottom padding applied to the sheet content
    static let bottomPadding: CGFloat = 18
}

public struct OverlayHeaderButton {
    public let text: LocalizedStringKey
    public let icon: Nicon
    public let action: () -> Void
}

// This view provides an overlay bottom sheet implementation that starts in a
// half-height (or middle) position. The user can drag it to a fullscreen (or
// top) position or can drag down to dismiss.
// Intended to present content that is flexible in height (e.g., a ScrollView).
struct OverlaySheetView<Content: View, HeaderContent: View>: View, KeyboardReadable {
    // MARK: - Properties
    @StateObject var model: OverlaySheetModel

    @State private var keyboardHeight: CGFloat = 0
    @State private var titleHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var title: LocalizedStringKey? = nil
    @State private var isFixedHeight: Bool = false
    @State private var bottomSafeArea: CGFloat = 0
    @State private var middlePreferredHeight: CGFloat? = nil
    @State private var childIgnoreSafeArea: Edge.Set = []

    let style: OverlayStyle
    let onDismiss: () -> Void
    let headerButton: OverlayHeaderButton?
    let headerContent: () -> HeaderContent
    let content: () -> Content

    private var keyboardIsVisible: Bool {
        return keyboardHeight > 0
    }

    private var applyBottomSafeAreaToSheet: Bool {
        childIgnoreSafeArea.contains(.bottom) && !(keyboardHeight > 0)
    }

    private var showHandle: Bool {
        !isFixedHeight && style.embedScrollView
    }

    // MARK: - View Functions
    private func isPortraitMode(_ outerGeometry: GeometryProxy) -> Bool {
        return outerGeometry.size.width < outerGeometry.size.height
    }

    private func getSpacerHeight(_ outerGeometry: GeometryProxy) -> CGFloat {
        let viewHeight = outerGeometry.size.height
        var size: CGFloat

        if isFixedHeight {
            switch self.model.position {
            case .top, .middle:
                size =
                    viewHeight - contentHeight
                    - (bottomSafeArea > 0 ? 0 : NeevaMenuUX.bottomPadding)
            case .dismissed:
                size = viewHeight
            }
        } else {
            switch model.position {
            case .top:
                size = 0

                if style.showTitle {
                    size += titleHeight
                }
            case .middle:
                if let middlePreferredHeight = middlePreferredHeight {
                    let approxContentHeight = middlePreferredHeight
                        + model.topBarHeight
                        + OverlaySheetUX.topPadding
                        + OverlaySheetUX.bottomPadding
                        + (applyBottomSafeAreaToSheet ? 0 : bottomSafeArea)
                    size = viewHeight - approxContentHeight
                } else if isPortraitMode(outerGeometry) {
                    size = viewHeight / 2
                } else {
                    size = 0
                }
            case .dismissed:
                return viewHeight
            }

            size = size + model.deltaHeight

            if !style.embedScrollView {
                size = max(size, viewHeight - contentHeight - NeevaMenuUX.bottomPadding)
            }
        }

        if keyboardHeight > 0 {
            size -= 12
        }

        let min: CGFloat = UIConstants.TopToolbarHeightWithToolbarButtonsShowing + headerHeight
        if size < min {
            size = min
        }

        return size
    }

    // MARK: - Views
    /// Controls height of the OverlaySheet
    private var topSpacer: some View {
        VStack(spacing: 0) {
            Spacer()

            // Without this, the smooth drag animation does not work
            Color.clear
        }
    }

    @ViewBuilder
    private var topBar: some View {
        VStack(spacing: 0) {
            if showHandle {
                Capsule()
                    .fill(Color.tertiaryLabel)
                    .frame(width: 32, height: 4)
                    .padding(15).background(Color.clear)  // make the selectable area larger
                    .accessibilityElement()
                    .accessibilityLabel("Pop-up controller")
                    .accessibilityValue(model.position.rawValue)
                    .accessibilityHint("Adjust the size of this pop-up window")
                    // TODO: make this action become disabled instead of doing nothing
                    .accessibilityAction(named: "Expand") {
                        withAnimation(.easeOut(duration: OverlaySheetUX.animationDuration)) {
                            self.model.position = .top
                        }
                    }
                    .accessibilityAction(named: model.position == .top ? "Collapse" : "Dismiss") {
                        if model.position == .top {
                            withAnimation(.easeOut(duration: OverlaySheetUX.animationDuration)) {
                                self.model.position = .middle
                            }
                        } else {
                            model.hide()
                        }
                    }
                    .padding(-15)
                    .padding(.top, 8)
            }

            HStack(spacing: 0) {
                if style.showTitle, let title = title {
                    Text(title)
                        .withFont(.headingMedium)
                        .foregroundColor(.label)
                        .padding(.leading, 16)
                    Spacer()
                    Button(action: onDismiss) {
                        Symbol(.xmark, style: .headingMedium, label: "Close")
                            .foregroundColor(.tertiaryLabel)
                            .tapTargetFrame()
                            .padding(.trailing, 4.5)
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.top, 8)
            .onHeightOfViewChanged { height in
                self.titleHeight = height
            }
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        self.content()
            .modifier(ViewHeightKey())
            .onPreferenceChange(OverlayTitlePreferenceKey.self) { self.title = $0 }
            .onPreferenceChange(OverlayIsFixedHeightPreferenceKey.self) {
                self.isFixedHeight = $0
            }
            .onPreferenceChange(OverlaySheetMiddleHeightPreferenceKey.self) {
                self.middlePreferredHeight = $0
            }
            .onPreferenceChange(OverlaySheetIgnoreSafeAreaPreferenceKey.self) {
                self.childIgnoreSafeArea = $0
            }
    }

    @ViewBuilder
    private var sheet: some View {
        VStack {
            VStack(spacing: 0) {
                self.topBar
                    .modifier(ViewHeightKey())
                    .onPreferenceChange(ViewHeightKey.self) { self.model.topBarHeight = $0 }

                if isFixedHeight {
                    sheetContent
                } else if !style.embedScrollView {
                    sheetContent
                } else {
                    ScrollView(model.position == .top ? [.vertical] : [], showsIndicators: false) {
                        sheetContent
                            .padding(.bottom, OverlaySheetUX.bottomPadding)
                    }
                }
            }
            .padding(.bottom, applyBottomSafeAreaToSheet ? bottomSafeArea : 0)
            .onHeightOfViewChanged { height in
                self.contentHeight = height
            }
            Spacer()
        }
        .background(
            Color(style.backgroundColor)
                .cornerRadius(16, corners: [.topLeading, .topTrailing])
                .ignoresSafeArea(edges: .bottom)
                .padding(.bottom, -12)
        )
        .highPriorityGesture(topDrag)
    }

    var body: some View {
        GeometryReader { outerGeometry in
            DismissBackgroundView(
                opacity: model.backdropOpacity, position: model.position,
                onDismiss: style.nonDismissible ? {} : onDismiss)

            VStack(spacing: 0) {
                // The height of this spacer is what controls the apparent height of
                // the sheet. By sizing this spacer instead of the sheet directly
                // we avoid encroaching on the safe area. That's because the spacer
                // cannot be made to have negative height.
                topSpacer
                    .frame(height: getSpacerHeight(outerGeometry))
                    .animation(.interactiveSpring(), value: model.deltaHeight)

                // Used to center the sheet within the container view.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sheet
                        // Constrain to full width in portrait mode.
                        .frame(
                            minWidth: isPortraitMode(outerGeometry)
                                ? outerGeometry.size.width : OverlaySheetUX.landscapeModeWidth,
                            maxWidth: isPortraitMode(outerGeometry)
                                ? outerGeometry.size.width : OverlaySheetUX.landscapeModeWidth
                        )
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, OverlaySheetUX.topPadding)
            .keyboardListener { height in
                withAnimation {
                    keyboardHeight = height
                }
            }
            .background(
                VStack {
                    if case .middle = model.position {
                        HStack(spacing: 0) {
                            Spacer().layoutPriority(0.5)

                            if let headerButton = headerButton {
                                Button(
                                    action: {
                                        headerButton.action()
                                        model.hide()
                                    },
                                    label: {
                                        HStack(spacing: 10) {
                                            Text(headerButton.text)
                                                .withFont(.labelLarge)
                                            Symbol(decorative: headerButton.icon)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                )
                                .buttonStyle(.neeva(.primary))
                                .padding(.horizontal, 6)
                                .layoutPriority(0.5)
                            }
                        }

                        headerContent()
                            .frame(maxWidth: .infinity)
                            .layoutPriority(0.5)
                    }
                }
                .modifier(ViewHeightKey())
                .onPreferenceChange(ViewHeightKey.self) { headerHeight = $0 - 12 }
                .position(
                    x: outerGeometry.size.width / 2,
                    y: getSpacerHeight(outerGeometry) - headerHeight / 2
                )

            )
        }
        .background(
            Color.clear
                .ignoresSafeArea(.keyboard)
                .safeAreaChanged { insets in
                    self.bottomSafeArea = insets.bottom
                }
        )
        .ignoresSafeArea(.container)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }

    // MARK: - Drag
    private var topDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isFixedHeight {
                    self.onDragChanged(value)
                }
            }
            .onEnded { value in
                if !isFixedHeight {
                    self.onDragEnded(value)
                }
            }
    }

    private func onDragChanged(_ value: DragGesture.Value) {
        self.model.deltaHeight += value.translation.height
    }

    // Update position based on how much delta height has been accumulated.
    // Set those values using withAnimation so the resulting UI changes are
    // applied smoothly.
    private func onDragEnded(_ value: DragGesture.Value) {
        self.model.deltaHeight += value.translation.height

        var newPosition = self.model.position
        if self.model.deltaHeight > OverlaySheetUX.slideThreshold {
            // Middle position only makes sense when the keyboard is hidden, and if
            // the delta is too large, then we just want to dismiss the sheet.
            if self.model.position == .top && !keyboardIsVisible
                && self.model.deltaHeight < 4 * OverlaySheetUX.slideThreshold
            {
                newPosition = .middle
            } else {
                self.model.hide()
                return
            }
        } else if self.model.deltaHeight < -OverlaySheetUX.slideThreshold {
            newPosition = .top
        }

        withAnimation(.easeOut(duration: OverlaySheetUX.animationDuration)) {
            self.model.position = newPosition
            self.model.deltaHeight = 0
        }
    }
}

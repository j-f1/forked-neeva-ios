// Copyright Neeva. All rights reserved.

import NeevaSupport
import SwiftUI

// This file provides an overlay bottom sheet implementation that starts in a
// half-height (or middle) position. The user can drag it to a fullscreen (or
// top) position or can drag down to dismiss.

struct OverlaySheetUX {
    // Number of points you have to drag the top bar to tigger an animation
    // of the overlay sheet to a new position.
    static let slideThreshold: CGFloat = 100

    // Duration of slide animations.
    static let animationDuration: Double = 0.2

    // Opacity of the backdrop when the overlay sheet is done animating open.
    static let backdropMaxOpacity: Double = 0.4

    // Width of the sheet when in landscape mode.
    static let landscapeModeWidth: CGFloat = 500
}

enum OverlaySheetPosition {
    case top
    case middle
    case dismissed
}

class OverlaySheetModel: ObservableObject {
    @Published var deltaHeight: CGFloat = 0
    @Published var position: OverlaySheetPosition = .dismissed
    @Published var backdropOpacity: Double = 0.0

    func show() {
        withAnimation(.easeOut(duration: OverlaySheetUX.animationDuration)) {
            self.position = .middle
            self.backdropOpacity = OverlaySheetUX.backdropMaxOpacity
        }
    }

    func hide() {
        withAnimation(.easeOut(duration: OverlaySheetUX.animationDuration)) {
            self.deltaHeight = 0
            self.position = .dismissed
            self.backdropOpacity = 0.0
        }
    }
}

// Intended to present content that is flexible in height (e.g., a ScrollView).
struct OverlaySheetView<Content: View>: View, KeyboardReadable {
    @StateObject var model: OverlaySheetModel

    @State private var keyboardHeight: CGFloat = 0
    @State private var topBarHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var title: String = ""
    @State private var isFixedHeight: Bool = false

    let onDismiss: () -> ()
    var content: () -> Content

    private var keyboardIsVisible: Bool {
        return keyboardHeight > 0
    }

    // The height of the spacer is a function of the outer geometry (i.e.,
    // that of our container) and the current delta height.
    private func getSpacerHeight(_ outerGeometry: GeometryProxy) -> CGFloat {
        var size: CGFloat
        if isFixedHeight {
            size = outerGeometry.size.height - contentHeight - topBarHeight
        } else {
            let defaultSize: CGFloat
            switch self.model.position {
            case .top:
                defaultSize = 0
            case .middle:
                if isPortraitMode(outerGeometry) {
                    defaultSize = outerGeometry.size.height / 2
                } else {
                    defaultSize = 0  // Landscape mode does not support half-height
                }
            case .dismissed:
                defaultSize = outerGeometry.size.height
            }
            size = defaultSize + self.model.deltaHeight
        }
        if size < 0 {
            size = 0
        }
        return size
    }

    // Applied to the top bar.
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

    var topBar: some View {
        VStack(spacing: 0) {
            if !isFixedHeight {
                RoundedRectangle(cornerRadius: 50)
                    .frame(width: 32, height: 4)
                    .foregroundColor(Color(UIColor.Neeva.Gray60))
                    .padding(.top, 8)
            }
            HStack(spacing: 0) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .padding(.leading, 16)
                Spacer()
                Button {
                    self.model.hide()
                } label: {
                    Symbol.system(.xmark, size: 16, weight: .semibold)
                        .foregroundColor(Color(UIColor.Neeva.Gray60))
                        .frame(width: 44, height: 44)
                        .padding(.trailing, 4.5)
                }
            }
            .padding(.top, 8)
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .gesture(topDrag)
    }

    var body: some View {
        GeometryReader { outerGeometry in
            ZStack {
                // The semi-transparent backdrop used to shade the content that lies below
                // the sheet.
                Color.black
                    .opacity(self.model.backdropOpacity)
                    .ignoresSafeArea()
                    .modifier(DismissalObserverModifier(backdropOpacity: self.model.backdropOpacity, position: self.model.position, onDismiss: self.onDismiss))
                    .onTapGesture {
                        self.model.hide()
                    }

                // Used to center the sheet within the container view.
                HStack(spacing: 0) {
                    Spacer()
                        .frame(minWidth: 0)

                    VStack(spacing: 0) {
                        // The height of this spacer is what controls the apparent height of
                        // the sheet. By sizing this spacer instead of the sheet directly
                        // we avoid encroaching on the safe area. That's because the spacer
                        // cannot be made to have negative height.
                        Spacer()
                            .frame(height: getSpacerHeight(outerGeometry))

                        VStack(spacing: 0) {
                            self.topBar
                                .modifier(ViewHeightKey())
                                .onPreferenceChange(ViewHeightKey.self) { self.topBarHeight = $0 }
                            self.content()
                                .modifier(ViewHeightKey())
                                .onPreferenceChange(ViewHeightKey.self) { self.contentHeight = $0 }
                                .onPreferenceChange(OverlaySheetTitlePreferenceKey.self) { self.title = $0 }
                                .onPreferenceChange(OverlaySheetIsFixedHeightPreferenceKey.self) { self.isFixedHeight = $0 }
                                .background(Color(UIColor.systemBackground))
                            if isFixedHeight {
                                Color(UIColor.systemBackground)
                                    .ignoresSafeArea(edges: .bottom)
                            }
                        }

                        // Position the card above the keyboard.
                        Color(UIColor.systemBackground)
                            .frame(height: keyboardHeight)
                    }
                    // Constrain to full width in portrait mode.
                    .frame(minWidth: isPortraitMode(outerGeometry) ? outerGeometry.size.width : OverlaySheetUX.landscapeModeWidth,
                           maxWidth: isPortraitMode(outerGeometry) ? outerGeometry.size.width : OverlaySheetUX.landscapeModeWidth)

                    Spacer()
                        .frame(minWidth: 0)
                }
                .ignoresSafeArea(edges: [.bottom])
            }
        }
        .navigationBarHidden(true)
        .onReceive(keyboardPublisher) { height in
            if height == 0 {
                keyboardHeight = 0
            } else {
                withAnimation(.easeInOut(duration: OverlaySheetUX.animationDuration * 2)) {
                    keyboardHeight = height
                    model.position = .top
                }
            }
        }
    }

    private func isPortraitMode(_ outerGeometry: GeometryProxy) -> Bool {
        return outerGeometry.size.width < outerGeometry.size.height
    }

    private func onDragChanged(_ value: DragGesture.Value) {
        self.model.deltaHeight += value.translation.height
    }

    // Update position based on how much delta height has been accumulated.
    // Set those values using withAnimation so the resulting UI changes are
    // applied smoothly.
    private func onDragEnded(_ value: DragGesture.Value) {
        self.model.deltaHeight += value.translation.height
        var newPosition = self.model.position;
        if self.model.deltaHeight > OverlaySheetUX.slideThreshold {
            if self.model.position == .top && !keyboardIsVisible {
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

// This PreferenceKey may be used by a child View of the OverlaySheetView
// to specify a title for the sheet.
//
// E.g.:
//
//    OverlaySheetView(..) {
//        SomeContent()
//            .overlaySheetTitle(title: "Some Title")
//    }
//
struct OverlaySheetTitlePreferenceKey: PreferenceKey {
    typealias Value = String
    static var defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
struct OverlaySheetTitleViewModifier: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content.preference(
            key: OverlaySheetTitlePreferenceKey.self,
            value: title)
    }
}
extension View {
    func overlaySheetTitle(title: String) -> some View {
        self.modifier(OverlaySheetTitleViewModifier(title: title))
    }
}

// This PreferenceKey may be used by a child View of the OverlaySheetView
// to specify that the content should be treated as fixed height.
struct OverlaySheetIsFixedHeightPreferenceKey: PreferenceKey {
    typealias Value = Bool
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}
struct OverlaySheetIsFixedHeightViewModifier: ViewModifier {
    let isFixedHeight: Bool
    func body(content: Content) -> some View {
        content.preference(
            key: OverlaySheetIsFixedHeightPreferenceKey.self,
            value: isFixedHeight)
    }
}
extension View {
    func overlaySheetIsFixedHeight(isFixedHeight: Bool) -> some View {
        self.modifier(OverlaySheetIsFixedHeightViewModifier(isFixedHeight: isFixedHeight))
    }
}

fileprivate struct DismissalObserverModifier: AnimatableModifier {
    var backdropOpacity: Double
    let position: OverlaySheetPosition
    let onDismiss: () -> ()

    var animatableData: Double {
        get { backdropOpacity }
        set { backdropOpacity = newValue
            if position == .dismissed && backdropOpacity == 0.0 {
                onDismiss()
            }
        }
    }

    func body(content: Content) -> some View {
        return content
    }
}

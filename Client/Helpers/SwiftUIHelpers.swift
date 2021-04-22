// Copyright Neeva. All rights reserved.

import Combine
import SwiftUI

// Optionally wraps an embedded view with a ScrollView based on a specified
// threshold height value. I.e., if the view needs to be larger than the
// specified value, then a ScrollView will be inserted.
public struct VerticalScrollViewIfNeeded<EmbeddedView>: View where EmbeddedView: View {
    var embeddedView: EmbeddedView
    let thresholdHeight: CGFloat

    public var body: some View {
        GeometryReader { geometry in
            if geometry.size.height < self.thresholdHeight {
                ScrollView {
                    self.embeddedView
                }
            } else {
                self.embeddedView
            }
        }
    }
}

// Detect if the keyboard is visible or not and publish that state.
// It can then be read via .onReceive on a View.
// From https://stackoverflow.com/questions/65784294/how-to-detect-if-keyboard-is-present-in-swiftui
// See also https://www.vadimbulavin.com/how-to-move-swiftui-view-when-keyboard-covers-text-field/
protocol KeyboardReadable {
    var keyboardPublisher: AnyPublisher<CGFloat, Never> { get }
}
extension KeyboardReadable {
    var keyboardPublisher: AnyPublisher<CGFloat, Never> {
        Publishers.Merge(
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardDidShowNotification)
                .map { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? CGFloat(0) },

            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .eraseToAnyPublisher()
    }
}

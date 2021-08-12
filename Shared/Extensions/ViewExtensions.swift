// Copyright © Neeva. All rights reserved.
import SwiftUI

// Enable cornerRadius to apply only to specific corners.
// From https://stackoverflow.com/questions/56760335/round-specific-corners-swiftui
private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect, byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension UIRectCorner {
    public static let top: UIRectCorner = [.topLeft, .topRight]
    public static let bottom: UIRectCorner = [.bottomLeft, .bottomRight]
    public static let left: UIRectCorner = [.topLeft, .bottomLeft]
    public static let right: UIRectCorner = [.topRight, .bottomRight]
}

extension View {
    /// Clips the views to a rectangle with only the specified corners rounded.
    public func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    /// Applies a toggle style that turns them from green to blue
    public func applyToggleStyle() -> some View {
        toggleStyle(SwitchToggleStyle(tint: Color.ui.adaptive.blue))
    }

    /// Sizes the view to 44×44 pixels, the standard tap target size
    public func tapTargetFrame() -> some View {
        frame(width: 44, height: 44)
    }
}

// From https://www.avanderlee.com/swiftui/conditional-view-modifier/
extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder public func `if`<Content: View>(
        _ condition: @autoclosure () -> Bool, transform: (Self) -> Content
    ) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }

    /// Applies the given transform if the given value is non-`nil`.
    /// - Parameters:
    ///   - value: The value to check
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the value is non-`nil`.
    @ViewBuilder public func `if`<Value, Content: View>(
        `let` value: @autoclosure () -> Value?, transform: (Value, Self) -> Content
    ) -> some View {
        if let value = value() {
            transform(value, self)
        } else {
            self
        }
    }
}

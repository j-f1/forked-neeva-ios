// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation
import Shared
import SwiftUI

public struct WalletTheme {
    public static let sharedBundle = Bundle(for: WalletBundleHookClass.self)
    public static let gradient = LinearGradient(
        colors: [.wallet.gradientStart, .wallet.gradientEnd], startPoint: .leading,
        endPoint: .trailing)
}

private class WalletBundleHookClass {}

extension UIColor {
    public enum wallet {
        public static let gradientStart = UIColor(
            named: "GradientStart", in: WalletTheme.sharedBundle, compatibleWith: nil)!
        public static let gradientEnd = UIColor(
            named: "GradientEnd", in: WalletTheme.sharedBundle, compatibleWith: nil)!
    }
}

extension Color {
    public enum wallet {
        public static let gradientStart = Color(UIColor.wallet.gradientStart)
        public static let gradientEnd = Color(UIColor.wallet.gradientEnd)
        public static let secondary = Color(
            light: Color.quaternarySystemFill, dark: Color.tertiarySystemFill)
        public static let primaryLabel = Color(light: Color.brand.white, dark: Color.black)
    }
}

public struct NeevaWalletButtonStyle: ButtonStyle {
    public enum VisualSpec {
        case primary
        case secondary
    }

    let visualSpec: VisualSpec
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder var background: some View {
        switch visualSpec {
        case .primary:
            WalletTheme.gradient
        case .secondary:
            Color.wallet.secondary
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(visualSpec == VisualSpec.primary ? .wallet.primaryLabel : .label)
            .padding(.vertical, 8)
            .frame(height: 48)
            .background(background)
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ButtonStyle where Self == NeevaWalletButtonStyle {
    public static func wallet(_ visualSpec: NeevaWalletButtonStyle.VisualSpec) -> Self {
        .init(visualSpec: visualSpec)
    }
}
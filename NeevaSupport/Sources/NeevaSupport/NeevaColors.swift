/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import SwiftUI

extension UIColor {
    public struct Neeva {
        public struct Brand {
            public static let Charcoal = UIColor(named: "Brand-Charcoal", in: Bundle.module, compatibleWith: nil)!
            public static let Blue = UIColor(named: "Brand-Blue", in: Bundle.module, compatibleWith: nil)!
            public static let Beige = UIColor(named: "Brand-Beige", in: Bundle.module, compatibleWith: nil)!
            public static let Polar = UIColor(named: "Brand-Polar", in: Bundle.module, compatibleWith: nil)!
            public static let Maya = UIColor(named: "Brand-Maya", in: Bundle.module, compatibleWith: nil)!
            public static let White = UIColor(named: "Brand-White", in: Bundle.module, compatibleWith: nil)!
            public static let Offwhite = UIColor(named: "Brand-Offwhite", in: Bundle.module, compatibleWith: nil)!
            public static let Pistachio = UIColor(named: "Brand-Pistachio", in: Bundle.module, compatibleWith: nil)!
            public static let Purple = UIColor(named: "Brand-Purple", in: Bundle.module, compatibleWith: nil)!
        }

        public struct UI {
            public static let Aqua = UIColor(named: "UI-Aqua", in: Bundle.module, compatibleWith: nil)!
            public static let Gray10 = UIColor(named: "UI-Gray10", in: Bundle.module, compatibleWith: nil)!
            public static let Gray20 = UIColor(named: "UI-Gray20", in: Bundle.module, compatibleWith: nil)!
            public static let Gray30 = UIColor(named: "UI-Gray30", in: Bundle.module, compatibleWith: nil)!
            public static let Gray60 = UIColor(named: "UI-Gray60", in: Bundle.module, compatibleWith: nil)!
            public static let Gray70 = UIColor(named: "UI-Gray70", in: Bundle.module, compatibleWith: nil)!
            public static let Gray96 = UIColor(named: "UI-Gray96", in: Bundle.module, compatibleWith: nil)!
            public static let Gray97 = UIColor(named: "UI-Gray97", in: Bundle.module, compatibleWith: nil)!
        }

        public static let DarkElevated = UIColor(named: "DarkElevated", in: Bundle.module, compatibleWith: nil)!
        public static let GlobeFavGray = UIColor(named: "GlobeFavGray", in: Bundle.module, compatibleWith: nil)!
        public static let Backdrop = UIColor(named: "Backdrop", in: Bundle.module, compatibleWith: nil)!
    }
}

extension Color {
    public struct Neeva {
        public struct Brand {
            public static let Charcoal = Color(UIColor.Neeva.Brand.Charcoal)
            public static let Blue = Color(UIColor.Neeva.Brand.Blue)
            public static let Beige = Color(UIColor.Neeva.Brand.Beige)
            public static let Polar = Color(UIColor.Neeva.Brand.Polar)
            public static let Maya = Color(UIColor.Neeva.Brand.Maya)
            public static let White = Color(UIColor.Neeva.Brand.White)
            public static let Offwhite = Color(UIColor.Neeva.Brand.Offwhite)
            public static let Pistachio = Color(UIColor.Neeva.Brand.Pistachio)
            public static let Purple = Color(UIColor.Neeva.Brand.Purple)
        }

        public struct UI {
            public static let Aqua = Color(UIColor.Neeva.UI.Aqua)
            public static let Gray10 = Color(UIColor.Neeva.UI.Gray10)
            public static let Gray20 = Color(UIColor.Neeva.UI.Gray20)
            public static let Gray30 = Color(UIColor.Neeva.UI.Gray30)
            public static let Gray60 = Color(UIColor.Neeva.UI.Gray60)
            public static let Gray70 = Color(UIColor.Neeva.UI.Gray70)
            public static let Gray96 = Color(UIColor.Neeva.UI.Gray96)
            public static let Gray97 = Color(UIColor.Neeva.UI.Gray97)
        }

        public static let DarkElevated = Color(UIColor.Neeva.DarkElevated)
        public static let GlobeFavGray = Color(UIColor.Neeva.GlobeFavGray)
        public static let Backdrop = Color(UIColor.Neeva.Backdrop)
    }
}

extension UIColor {
    public struct TextField {
        public static func background(isPrivate: Bool) -> UIColor { return isPrivate ? .black : UIColor.systemFill }
        public static func textAndTint(isPrivate: Bool) -> UIColor { return isPrivate ? .white : .label }
        public static func disabledTextAndTint(isPrivate: Bool) -> UIColor { isPrivate ? UIColor(red: 235, green: 235, blue: 245, alpha: 0.6) : .secondaryLabel }
    }
}
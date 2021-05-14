//
//  NeevaMenuRowButtonView.swift
//  
//
//  Created by Stuart Allen on 13/03/21.
//  Copyright © 2021 Neeva. All rights reserved.
//

import NeevaSupport
import SwiftUI

public struct NeevaMenuRowButtonView: View {
    let label: String
    let nicon: Nicon?
    let symbol: SFSymbol?

    /// - Parameters:
    ///   - label: The text displayed on the button
    ///   - nicon: The Nicon to use
    public init(label: String, nicon: Nicon){
        self.label = label
        self.nicon = nicon
        self.symbol = nil
    }

    /// - Parameters:
    ///   - label: The text displayed on the button
    ///   - symbol: The SFSymbol to use
    public init(label: String, symbol: SFSymbol){
        self.label = label
        self.nicon = nil
        self.symbol = symbol
    }

    public var body: some View {
        Group{
            HStack(spacing: 0) {
                Text(label)
                    .foregroundColor(Color(UIColor.theme.popupMenu.textColor))
                    .font(.system(size: 17))

                Spacer()

                Group {
                    if let nicon = self.nicon {
                        Symbol.neeva(nicon, size: 18)
                    } else if let symbol = self.symbol {
                        Symbol.system(symbol, size: 18)
                    }
                }
                .foregroundColor(Color(UIColor.theme.popupMenu.buttonColor))
            }
        }
        .background(Color(UIColor.theme.popupMenu.foreground))
    }
}

struct NeevaMenuRowButtonView_Previews: PreviewProvider {
    static var previews: some View {
        NeevaMenuRowButtonView(label: "Test", nicon: .gear)
    }
}
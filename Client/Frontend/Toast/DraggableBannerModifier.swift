// Copyright Neeva. All rights reserved.

import Foundation
import SwiftUI

protocol BannerViewDelegate: AnyObject {
    func dismiss()
    func draggingUpdated()
    func draggingEnded(dismissing: Bool)
}

struct DraggableBannerModifier: ViewModifier {
    @State private var offset: CGFloat = 0
    private var opacity: CGFloat {
        let delta = abs(offset) - ToastViewUX.threshold
        return delta > 0 ? 1 - delta / (ToastViewUX.threshold * 3) : 1
    }

    var draggingUpdated: (() -> Void)?
    var draggingEnded: ((Bool) -> Void)?

    private var drag: some Gesture {
        DragGesture()
            .onChanged {
                self.offset = $0.translation.height
                draggingUpdated?()
            }
            .onEnded {
                var dismissing = false
                if abs($0.predictedEndTranslation.height) > ToastViewUX.height * 1.5 {
                    self.offset = $0.predictedEndTranslation.height
                    dismissing = true
                } else if abs($0.translation.height) > ToastViewUX.height {
                    dismissing = true
                } else {
                    self.offset = 0
                }

                draggingEnded?(dismissing)
            }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .gesture(drag)
            .opacity(Double(opacity))
            .animation(.interactiveSpring(), value: offset)
    }
}
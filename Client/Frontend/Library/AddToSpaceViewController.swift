//
//  AddToSpaceViewController.swift
//  Client
//
//  Copyright © 2020 Neeva. All rights reserved.
//

import SwiftUI
import Shared

struct AddToSpaceRootView: View {
    var overlaySheetModel = OverlaySheetModel()

    @StateObject var request: AddToSpaceRequest
    var onDismiss: () -> ()
    var onOpenURL: (URL) -> ()

    private var overlaySheetTitle: String {
        switch request.mode {
        case .saveToNewSpace:
            return "Create Space"
        case .saveToExistingSpace:
            return "Save to Spaces"
        }
    }

    private var overlaySheetIsFixedHeight: Bool {
        switch request.mode {
        case .saveToNewSpace:
            return true
        case .saveToExistingSpace:
            return false
        }
    }

    var body: some View {
        let config = OverlaySheetConfig(showTitle: true)
        OverlaySheetView(model: self.overlaySheetModel, config: config, onDismiss: { self.onDismiss() }) {
            AddToSpaceView(
                request: self.request, onDismiss: {
                    // The user made a selection. Store that and run the animation to hide the
                    // sheet. When that completes, we'll run the provided onDismiss callback.
                    self.overlaySheetModel.hide()
                })
                .environment(\.onOpenURL, { self.onOpenURL($0) })
                .overlaySheetTitle(title: self.overlaySheetTitle)
                .overlaySheetIsFixedHeight(isFixedHeight: self.overlaySheetIsFixedHeight)
        }
        .onAppear() {
            // It seems to be necessary to delay starting the animation until this point to
            // avoid a visual artifact.
            DispatchQueue.main.async {
                self.overlaySheetModel.show()
            }
        }
    }
}

class AddToSpaceViewController: UIHostingController<AddToSpaceRootView> {
    init(request: AddToSpaceRequest, onDismiss: @escaping () -> (), onOpenURL: @escaping (URL) -> ()) {
        super.init(rootView: AddToSpaceRootView(request: request, onDismiss: onDismiss, onOpenURL: onOpenURL))

        // Make sure the theme is propagated properly, even if it changes while the sheet
        // is visible. This is needed for UI that does not just take its colors from the
        // current Theme object.
        self.overrideUserInterfaceStyle = ThemeManager.instance.current.userInterfaceStyle
        NotificationCenter.default.addObserver(forName: .DisplayThemeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.overrideUserInterfaceStyle = ThemeManager.instance.current.userInterfaceStyle
        }
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // By default, a UIHostingController opens as an opaque layer, so we override
        // that behavior here.
        view.backgroundColor = .clear
    }
}

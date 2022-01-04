// Copyright Neeva. All rights reserved.

import Combine
import Shared
import SwiftUI
import UIKit

class ToastDefaults: NSObject {
    var toast: ToastView?
    var toastProgressViewModel: ToastProgressViewModel?

    private var requestListener: AnyCancellable?

    func showToastForClosedTabs(_ savedTabs: [SavedTab], tabManager: TabManager) {
        guard savedTabs.count > 0 else {
            return
        }

        var toastText: LocalizedStringKey = "Tab Closed"

        if savedTabs.count > 0 {
            if savedTabs.count > 1 {
                toastText = "\(savedTabs.count) Tabs Closed"
            }

            let toastContent = ToastViewContent(
                normalContent: ToastStateContent(
                    text: toastText, buttonText: "restore",
                    buttonAction: {
                        let bvc = SceneDelegate.getBVC(with: tabManager.scene)
                        _ = bvc.tabManager.restoreSavedTabs(savedTabs)
                    }))

            guard
                let toastViewManager = SceneDelegate.getCurrentSceneDelegate(
                    with: tabManager.scene)?.toastViewManager
            else {
                return
            }

            let toastView = toastViewManager.makeToast(content: toastContent)
            toast = toastView
            toastViewManager.enqueue(view: toastView)
        }
    }

    func showToastForDownload(download: Download, toastViewManager: ToastViewManager) {
        resetProgress()

        download.delegate = self

        let normalContent = ToastStateContent(text: "Downloading", buttonText: "cancel") {
            download.cancel()
        }
        let completedContent = ToastStateContent(text: "Downloaded", buttonText: "open") {
            openDownloadsFolderInFilesApp()
        }
        let failedContent = ToastStateContent(text: "Download Failed")

        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        let toastView = toastViewManager.makeToast(
            content: toastContent, toastProgressViewModel: toastProgressViewModel,
            autoDismiss: false)
        toast = toastView
        toastViewManager.enqueue(view: toastView, at: .first)
    }

    func showToastForAddToSpaceUI(bvc: BrowserViewController, request: AddToSpaceRequest) {
        toastProgressViewModel = ToastProgressViewModel()
        toastProgressViewModel?.status = .inProgress

        requestListener = request.$state.sink { [weak self] updatedState in
            guard let self = self else { return }

            if updatedState == .failed {
                self.toastProgressViewModel?.status = .failed
            } else {
                self.toastProgressViewModel?.status = .success
                if let spaceID = request.targetSpaceID {
                    SpaceStore.shared.refreshSpace(spaceID: spaceID)
                }
                self.requestListener = SpaceStore.shared.$state.sink { state in
                    bvc.chromeModel.urlInSpace = false
                    self.requestListener?.cancel()
                }
            }
        }

        let spaceName = request.targetSpaceName ?? "## Unknown ##"
        let (toastText, completedText, deleted) = request.textInfo

        let buttonAction = {
            if let spaceID = request.targetSpaceID {
                bvc.gridModel.openSpace(
                    spaceID: spaceID)
            } else {
                bvc.gridModel.showSpaces()
            }
        }

        let failedAction = {
            if deleted {
                request.deleteFromExistingSpace(
                    id: request.targetSpaceID ?? "", name: request.targetSpaceName ?? "")
            } else {
                request.addToExistingSpace(
                    id: request.targetSpaceID ?? "", name: request.targetSpaceName ?? "")
            }

            self.showToastForAddToSpaceUI(bvc: bvc, request: request)
        }

        let normalContent = ToastStateContent(
            text: toastText, buttonText: "open space", buttonAction: buttonAction)
        let completedContent = ToastStateContent(
            text: completedText, buttonText: "open space", buttonAction: buttonAction)
        let failedContent = ToastStateContent(
            text: "Failed to \(deleted ? "delete from" : "save to") \"\(spaceName)\"",
            buttonText: "try again",
            buttonAction: failedAction)
        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        guard
            let toastViewManager = SceneDelegate.getCurrentSceneDelegate(for: bvc.view)
                .toastViewManager
        else {
            return
        }

        let toastView = toastViewManager.makeToast(
            content: toastContent, toastProgressViewModel: toastProgressViewModel,
            autoDismiss: false)
        toast = toastView
        toastViewManager.enqueue(view: toastView)
    }

    func showToastForRemoveFromSpace(
        bvc: BrowserViewController, request: DeleteSpaceItemsRequest,
        undoDeletion: @escaping () -> Void, retryDeletion: @escaping () -> Void
    ) {
        resetProgress()

        requestListener = request.$state.sink { [weak self] updatedState in
            guard let self = self else { return }

            if updatedState == .failure {
                self.toastProgressViewModel?.status = .failed
            } else {
                self.toastProgressViewModel?.status = .success
            }
        }

        let normalContent = ToastStateContent(text: "Removing item from Space")
        let completedContent = ToastStateContent(
            text: "Item removed from Space", buttonText: "undo", buttonAction: undoDeletion)
        let failedContent = ToastStateContent(
            text: "Failed to remove item from Space",
            buttonText: "try again",
            buttonAction: retryDeletion)
        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        guard
            let toastViewManager = SceneDelegate.getCurrentSceneDelegate(for: bvc.view)
                .toastViewManager
        else {
            return
        }

        let toastView = toastViewManager.makeToast(
            content: toastContent, toastProgressViewModel: toastProgressViewModel,
            autoDismiss: false)
        toast = toastView
        toastViewManager.enqueue(view: toastView)
    }

    func showToastForFeedback(request: FeedbackRequest, toastViewManager: ToastViewManager) {
        let normalContent = ToastStateContent(text: "Feedback Submitted!")
        let toastContent = ToastViewContent(
            normalContent: normalContent)

        let toastView = toastViewManager.makeToast(
            content: toastContent,
            toastProgressViewModel: toastProgressViewModel)
        toast = toastView
        toastViewManager.enqueue(view: toastView)
    }

    func showToastForSetPreferredProvider(
        request: PreferredProviderRequest, toastViewManager: ToastViewManager
    ) {
        resetProgress()

        requestListener = request.$state.sink { [weak self] updatedState in
            guard let self = self else { return }

            switch updatedState {
            case .inProgress:
                self.toastProgressViewModel?.status = .inProgress
            case .success:
                self.toastProgressViewModel?.status = .success
            case .failed:
                self.toastProgressViewModel?.status = .failed
            }
        }

        let failedAction = {
            request.setPreferredProvider()
            self.showToastForSetPreferredProvider(
                request: request, toastViewManager: toastViewManager)
        }

        let normalContent = ToastStateContent(text: "Saving preference")
        let completedContent = ToastStateContent(text: "Preference saved!", buttonText: "Got it")

        let failedContent = ToastStateContent(
            text: "Failed to save preference",
            buttonText: "try again",
            buttonAction: failedAction)
        let toastContent = ToastViewContent(
            normalContent: normalContent, completedContent: completedContent,
            failedContent: failedContent)

        let toastView = toastViewManager.makeToast(
            content: toastContent,
            toastProgressViewModel: toastProgressViewModel, autoDismiss: false)
        toast = toastView
        toastViewManager.enqueue(view: toastView)
    }

    private func resetProgress() {
        toastProgressViewModel = ToastProgressViewModel()
        toastProgressViewModel?.status = .inProgress
    }
}

extension ToastDefaults: DownloadDelegate {
    func download(_ download: Download, didDownloadBytes bytesDownloaded: Int64) {

    }

    func download(_ download: Download, didFinishDownloadingTo location: URL) {
        toastProgressViewModel?.status = .success
        downloadComplete()
    }

    func download(_ download: Download, didCompleteWithError error: Error?) {
        if error != nil {
            print("Download failed with error:", error as Any)

            toastProgressViewModel?.status = .success
            downloadComplete()
        }
    }

    func downloadComplete() {
        self.toast = nil
    }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Combine
import Shared
import SnapKit
import SwiftUI

private let ToolbarBaseAnimationDuration: CGFloat = 0.2

class TabScrollingController: NSObject, ObservableObject {
    enum ScrollDirection {
        case up
        case down
    }

    enum ToolbarState {
        case collapsed
        case visible
        case animating
    }

    @Published var headerTopOffset: CGFloat = 0
    @Published var footerBottomOffset: CGFloat = 0

    private let chromeModel: TabChromeModel

    init(tabManager: TabManager, chromeModel: TabChromeModel) {
        self.scrollView = tabManager.selectedTab?.webView!.scrollView
        self.chromeModel = chromeModel
        super.init()

        tabManager.selectedTabPublisher
            .sink { [unowned self] newTab in
                scrollView?.delegate = nil
                scrollView?.removeGestureRecognizer(panGesture)

                if let tab = newTab, let scrollView = tab.webView?.scrollView {
                    scrollView.addGestureRecognizer(panGesture)
                    scrollView.delegate = self

                    self.scrollView = scrollView

                    tabSubscriptions = []
                    tab.$isLoading
                        .assign(to: \.tabIsLoading, on: self)
                        .store(in: &tabSubscriptions)
                } else {
                    scrollView = nil
                    tabSubscriptions = []
                }
            }
            .store(in: &subscriptions)
    }

    private var subscriptions: Set<AnyCancellable> = []
    private var tabSubscriptions: Set<AnyCancellable> = []
    private var tabIsLoading = false

    weak var header: UIView?
    weak var footer: UIView?
    weak var safeAreaView: UIView?

    fileprivate var isZoomedOut = false
    fileprivate var lastZoomedScale: CGFloat = 0
    fileprivate var isUserZoom = false

    fileprivate lazy var panGesture: UIPanGestureRecognizer = { [unowned self] in
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        panGesture.allowedScrollTypesMask = .all
        return panGesture
    }()

    fileprivate var scrollView: UIScrollView?
    fileprivate var contentOffset: CGPoint { scrollView?.contentOffset ?? .zero }
    fileprivate var contentSize: CGSize { scrollView?.contentSize ?? .zero }
    fileprivate var scrollViewHeight: CGFloat { scrollView?.frame.height ?? 0 }
    var headerHeight: CGFloat {
        if let header = header, let safeAreaView = safeAreaView {
            return header.frame.height - safeAreaView.safeAreaInsets.top
        } else {
            return 0
        }
    }
    fileprivate var topScrollHeight: CGFloat {
        return headerHeight
    }
    fileprivate var bottomScrollHeight: CGFloat { footer?.frame.height ?? 0 }

    fileprivate var lastContentOffset: CGFloat = 0
    fileprivate var scrollDirection: ScrollDirection = .down
    fileprivate var toolbarState: ToolbarState = .visible

    func showToolbars(animated: Bool, completion: ((_ finished: Bool) -> Void)? = nil) {
        if toolbarState == .visible {
            completion?(true)
            return
        }
        toolbarState = .visible
        let durationRatio = abs(headerTopOffset / topScrollHeight)
        let actualDuration = TimeInterval(ToolbarBaseAnimationDuration * durationRatio)
        self.animateToolbarsWithOffsets(
            animated,
            duration: actualDuration,
            headerOffset: 0,
            footerOffset: 0,
            alpha: 1,
            completion: completion)
    }

    fileprivate func hideToolbars(animated: Bool, completion: ((_ finished: Bool) -> Void)? = nil) {
        if toolbarState == .collapsed {
            completion?(true)
            return
        }
        toolbarState = .collapsed
        let durationRatio = abs((topScrollHeight + headerTopOffset) / topScrollHeight)
        let actualDuration = TimeInterval(ToolbarBaseAnimationDuration * durationRatio)
        self.animateToolbarsWithOffsets(
            animated,
            duration: actualDuration,
            headerOffset: -topScrollHeight,
            footerOffset: bottomScrollHeight,  // makes sure toolbar is hidden all the way
            alpha: 0,
            completion: completion)
    }

    func contentSizeDidChange() {
        if !checkScrollHeightIsLargeEnoughForScrolling() && headerTopOffset != 0 {
            showToolbars(animated: true, completion: nil)
        }
    }

    func updateMinimumZoom() {
        guard let scrollView = scrollView else {
            return
        }
        self.isZoomedOut = roundNum(scrollView.zoomScale) == roundNum(scrollView.minimumZoomScale)
        self.lastZoomedScale = self.isZoomedOut ? 0 : scrollView.zoomScale
    }

    func setMinimumZoom() {
        guard let scrollView = scrollView else {
            return
        }
        if self.isZoomedOut
            && roundNum(scrollView.zoomScale) != roundNum(scrollView.minimumZoomScale)
        {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
    }

    func resetZoomState() {
        self.isZoomedOut = false
        self.lastZoomedScale = 0
    }

    fileprivate func roundNum(_ num: CGFloat) -> CGFloat {
        return round(100 * num) / 100
    }
}

extension TabScrollingController {
    fileprivate var isBouncingAtBottom: Bool {
        guard let scrollView = scrollView else { return false }
        return scrollView.contentOffset.y
            > (scrollView.contentSize.height - scrollView.frame.size.height)
            && scrollView.contentSize.height > scrollView.frame.size.height
    }

    @objc fileprivate func handlePan(_ gesture: UIPanGestureRecognizer) {
        if tabIsLoading {
            return
        }

        if let containerView = scrollView?.superview {
            let translation = gesture.translation(in: containerView)
            let delta = lastContentOffset - translation.y

            if delta > 0 {
                scrollDirection = .down
            } else if delta < 0 {
                scrollDirection = .up
            }

            lastContentOffset = translation.y
            if checkRubberbandingForDelta(delta) && checkScrollHeightIsLargeEnoughForScrolling() {
                let bottomIsNotRubberbanding =
                    contentOffset.y + scrollViewHeight < contentSize.height
                let topIsRubberbanding = contentOffset.y <= 0
                if (toolbarState != .collapsed || topIsRubberbanding) && bottomIsNotRubberbanding {
                    scrollWithDelta(delta)
                }

                if headerTopOffset == -topScrollHeight && footerBottomOffset == bottomScrollHeight {
                    toolbarState = .collapsed
                } else if headerTopOffset == 0 && footerBottomOffset == 0 {
                    toolbarState = .visible
                } else {
                    toolbarState = .animating
                }
            }

            if gesture.state == .ended || gesture.state == .cancelled {
                lastContentOffset = 0
            }
        }
    }

    fileprivate func checkRubberbandingForDelta(_ delta: CGFloat) -> Bool {
        return
            !((delta < 0 && contentOffset.y + scrollViewHeight > contentSize.height
            && scrollViewHeight < contentSize.height) || contentOffset.y < delta)
    }

    fileprivate func scrollWithDelta(_ delta: CGFloat) {
        if scrollViewHeight >= contentSize.height {
            return
        }

        var updatedOffset = headerTopOffset - delta
        headerTopOffset = clamp(updatedOffset, min: -topScrollHeight, max: 0)
        if isHeaderDisplayedForGivenOffset(updatedOffset) {
            scrollView?.contentOffset = CGPoint(x: contentOffset.x, y: contentOffset.y - delta)
        }

        updatedOffset = footerBottomOffset + delta
        footerBottomOffset = clamp(updatedOffset, min: 0, max: bottomScrollHeight)

        let alpha = 1 - abs(headerTopOffset / topScrollHeight)
        chromeModel.controlOpacity = Double(alpha)
    }

    fileprivate func isHeaderDisplayedForGivenOffset(_ offset: CGFloat) -> Bool {
        return offset > -topScrollHeight && offset < 0
    }

    fileprivate func clamp(_ y: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if y >= max {
            return max
        } else if y <= min {
            return min
        }
        return y
    }

    fileprivate func animateToolbarsWithOffsets(
        _ animated: Bool, duration: TimeInterval, headerOffset: CGFloat, footerOffset: CGFloat,
        alpha: CGFloat, completion: ((_ finished: Bool) -> Void)?
    ) {
        guard let scrollView = scrollView else { return }
        let initialContentOffset = scrollView.contentOffset

        // If this function is used to fully animate the toolbar from hidden to shown, keep the page from scrolling by adjusting contentOffset,
        // Otherwise when the toolbar is hidden and a link navigated, showing the toolbar will scroll the page and
        // produce a ~50px page jumping effect in response to tap navigations.
        let isShownFromHidden = headerTopOffset == -topScrollHeight && headerOffset == 0

        let animation: () -> Void = {
            if isShownFromHidden {
                scrollView.contentOffset = CGPoint(
                    x: initialContentOffset.x, y: initialContentOffset.y + self.topScrollHeight)
            }
            self.headerTopOffset = headerOffset
            self.footerBottomOffset = footerOffset
            self.header?.superview?.layoutIfNeeded()
        }

        DispatchQueue.main.async { [self] in
            if animated {
                withAnimation(.easeInOut(duration: duration)) {
                    chromeModel.controlOpacity = Double(alpha)
                }
                UIView.animate(
                    withDuration: duration, delay: 0, options: .allowUserInteraction,
                    animations: animation, completion: completion)
            } else {
                chromeModel.controlOpacity = Double(alpha)
                animation()
                completion?(true)
            }
        }
    }

    fileprivate func checkScrollHeightIsLargeEnoughForScrolling() -> Bool {
        return (UIScreen.main.bounds.size.height + 2 * UIConstants.ToolbarHeight)
            < scrollView?.contentSize.height ?? 0
    }
}

extension TabScrollingController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

extension TabScrollingController: UIScrollViewDelegate {
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if tabIsLoading || isBouncingAtBottom {
            return
        }

        if (decelerate || (toolbarState == .animating && !decelerate))
            && checkScrollHeightIsLargeEnoughForScrolling()
        {
            if scrollDirection == .up {
                showToolbars(animated: true)
            } else if scrollDirection == .down {
                hideToolbars(animated: true)
            }
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Only mess with the zoom level if the user did not initate the zoom via a zoom gesture
        if self.isUserZoom {
            return
        }

        //scrollViewDidZoom will be called multiple times when a rotation happens.
        // In that case ALWAYS reset to the minimum zoom level if the previous state was zoomed out (isZoomedOut=true)
        if isZoomedOut {
            scrollView.zoomScale = scrollView.minimumZoomScale
        } else if roundNum(scrollView.zoomScale) > roundNum(self.lastZoomedScale)
            && self.lastZoomedScale != 0
        {
            //When we have manually zoomed in we want to preserve that scale.
            //But sometimes when we rotate a larger zoomScale is appled. In that case apply the lastZoomedScale
            scrollView.zoomScale = self.lastZoomedScale
        }
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        self.isUserZoom = true
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat
    ) {
        self.isUserZoom = false
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        if toolbarState == .collapsed {
            showToolbars(animated: true)
            return false
        }
        return true
    }
}
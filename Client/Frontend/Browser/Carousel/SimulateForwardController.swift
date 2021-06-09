// Copyright Neeva. All rights reserved.

import UIKit

class SimulateForwardController:
    UIViewController, TabEventHandler, TabManagerDelegate, SimulateForwardAnimatorDelegate {

    func simulateForwardAnimatorCommittedForward(_ animator: SimulateForwardAnimator) {
        guard let tab = self.tabManager.selectedTab, let urls = self.forwardUrlMap[tab.tabUUID]! else {
            return
        }

        let index = urls.firstIndex(of: tab.currentURL()!) ?? 0
        assert(index < urls.count - 1) // If we are here, we have already fake animated and it is too late
        tab.loadRequest(URLRequest(url: urls[index + 1]))
        return
    }

    var animator: SimulateForwardAnimator!
    var blankView: UIView!
    var tabManager: TabManager
    var forwardUrlMap = [String: [URL]?]()

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)

        register(self, forTabEvents: .didChangeURL)
        tabManager.addDelegate(self)

        self.animator = SimulateForwardAnimator(
            animatingView: self.view,
            webViewContainer: BrowserViewController.foregroundBVC().webViewContainer)
        self.animator.delegate = self

    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        blankView = UIView()
        blankView.backgroundColor = .white
        self.view.addSubview(blankView)

        blankView.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.width.equalToSuperview().offset(-100)
        }
    }

    func tab(_ tab: Tab, didChangeURL url: URL) {
        guard let url = tab.webView?.url, tab == tabManager.selectedTab  else {
            return
        }

        if let query = neevaSearchEngine.queryForSearchURL(url), !query.isEmpty {
            forwardUrlMap[tab.tabUUID] = []
            SearchResultsController.getSearchResults(for: query) {result in
                switch result {
                case .failure(let error):
                    let _ = error as NSError
                    self.forwardUrlMap[tab.tabUUID] = nil
                    self.view.isHidden = true
                case .success(let results):
                    self.forwardUrlMap[tab.tabUUID] = results
                    self.view.isHidden = false
                }
            }
        }

        guard let urls = self.forwardUrlMap[tab.tabUUID] else {
            return
        }

        guard let index = urls?.firstIndex(of: url), index < (urls?.count ?? 0 - 2) else {
            forwardUrlMap[tab.tabUUID] = nil
            view.isHidden = true
            return
        }
    }

    func tabManager(_ tabManager: TabManager, didSelectedTabChange selected: Tab?, previous: Tab?, isRestoring: Bool) {
        guard let tabUUID = selected?.tabUUID else {
            return
        }
        view.isHidden = (self.forwardUrlMap[tabUUID] == nil)
    }

    func tabManager(_ tabManager: TabManager, didAddTab tab: Tab, isRestoring: Bool) {}

    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Tab, isRestoring: Bool) {}

    func tabManagerDidRestoreTabs(_ tabManager: TabManager) {}

    func tabManagerDidAddTabs(_ tabManager: TabManager) {}

    func tabManagerDidRemoveAllTabs(_ tabManager: TabManager, toast: ButtonToast?) {}
}
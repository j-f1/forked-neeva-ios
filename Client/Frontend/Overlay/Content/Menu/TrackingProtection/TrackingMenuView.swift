// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Defaults
import SFSafeSymbols
import Shared
import Storage
import SwiftUI

private enum TrackingMenuUX {
    static let hallOfShameElementSpacing: CGFloat = 8
    static let hallOfShameRowSpacing: CGFloat = 60
    static let hallOfShameElementFaviconSize: CGFloat = 25
}

struct HallOfShameDomain {
    let domain: TrackingEntity
    let count: Int
}

class TrackingStatsViewModel: ObservableObject {
    var numTrackers: Int {
        if let numTrackersTesting = numTrackersTesting {
            return numTrackersTesting
        } else {
            return selectedTab?.contentBlocker?.stats.domains.count ?? 0
        }
    }

    @Published private(set) var numDomains = 0
    @Published private(set) var hallOfShameDomains = [HallOfShameDomain]()
    @Published var preventTrackersForCurrentPage: Bool {
        didSet {
            ClientLogger.shared.logCounter(
                preventTrackersForCurrentPage ? .TurnOnBlockTracking : .TurnOffBlockTracking,
                attributes: EnvironmentHelper.shared.getAttributes() + [
                    ClientLogCounterAttribute(
                        key: LogConfig.TrackingProtectionAttribute.toggleProtectionForURL,
                        value: selectedTab?.currentURL()?.absoluteString)
                ]
            )

            guard let domain = selectedTab?.currentURL()?.host else {
                return
            }

            TrackingPreventionConfig.updateAllowList(
                with: domain, allowed: !preventTrackersForCurrentPage
            ) {
                self.selectedTab?.contentBlocker?.notifiedTabSetupRequired()
                self.selectedTab?.reload()
                self.refreshStats()
            }

        }
    }

    var viewVisible: Bool = false

    private var selectedTab: Tab? = nil {
        didSet {
            statsSubscription = nil
        }
    }

    private var subscriptions: Set<AnyCancellable> = []
    private var statsSubscription: AnyCancellable? = nil

    // read by tests
    private(set) var trackers: [TrackingEntity] {
        didSet {
            onDataUpdated()
        }
    }

    init(tabManager: TabManager) {
        self.selectedTab = tabManager.selectedTab
        self.preventTrackersForCurrentPage =
            !Defaults[.unblockedDomains].contains(selectedTab?.currentURL()?.host ?? "")
        let trackingData = TrackingEntity.getTrackingDataForCurrentTab(
            stats: selectedTab?.contentBlocker?.stats)
        self.numDomains = trackingData.numDomains
        self.trackers = trackingData.trackingEntities
        tabManager.selectedTabPublisher.assign(to: \.selectedTab, on: self).store(
            in: &subscriptions)
        onDataUpdated()
    }

    /// FOR TESTING ONLY
    private(set) var numTrackersTesting: Int?

    /// For usage with static data and testing only
    init(testingData: TrackingData) {
        self.preventTrackersForCurrentPage = true
        self.numDomains = testingData.numDomains
        self.trackers = testingData.trackingEntities
        self.numTrackersTesting = testingData.numTrackers
        onDataUpdated()
    }

    func refreshStats() {
        guard let tab = selectedTab else {
            return
        }

        let trackingData = TrackingEntity.getTrackingDataForCurrentTab(
            stats: tab.contentBlocker?.stats)
        self.numDomains = trackingData.numDomains
        self.trackers = trackingData.trackingEntities
        onDataUpdated()
        statsSubscription = selectedTab?.contentBlocker?.$stats
            .filter { [weak self] _ in self?.viewVisible ?? false }
            .map { TrackingEntity.getTrackingDataForCurrentTab(stats: $0) }
            .sink { [weak self] data in
                guard let self = self else { return }
                self.numDomains = data.numDomains
                self.trackers = data.trackingEntities
                self.onDataUpdated()
            }
    }

    func onDataUpdated() {
        hallOfShameDomains =
            trackers
            .reduce(into: [:]) { dict, tracker in dict[tracker] = (dict[tracker] ?? 0) + 1 }
            .map { HallOfShameDomain(domain: $0.key, count: $0.value) }
            .sorted(by: { $0.count > $1.count })
            .prefix(3)
            .toArray()
    }
}

struct TrackingMenuFirstRowElement: View {
    let label: LocalizedStringKey
    let num: Int

    var body: some View {
        GroupedCell(alignment: .leading) {
            VStack(alignment: .leading) {
                Text(label).withFont(.headingMedium).foregroundColor(.secondaryLabel)
                Text("\(num)").withFont(.displayMedium)
            }
            .padding(.bottom, 4)
            .padding(.vertical, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(num) \(Text(label)) blocked"))
            .accessibilityIdentifier("TrackingMenu.TrackingMenuFirstRowElement")
        }
    }
}

struct HallOfShameElement: View {
    let hallOfShameDomain: HallOfShameDomain

    var body: some View {
        HStack(spacing: TrackingMenuUX.hallOfShameElementSpacing) {
            Image(hallOfShameDomain.domain.rawValue).resizable().cornerRadius(5)
                .frame(
                    width: TrackingMenuUX.hallOfShameElementFaviconSize,
                    height: TrackingMenuUX.hallOfShameElementFaviconSize)
            Text("\(hallOfShameDomain.count)").withFont(.displayMedium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(hallOfShameDomain.count) trackers blocked from \(hallOfShameDomain.domain.rawValue)"
        )
        .accessibilityIdentifier("TrackingMenu.HallOfShameElement")
    }
}

struct HallOfShameView: View {
    let hallOfShameDomains: [HallOfShameDomain]

    var body: some View {
        GroupedCell(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("Hall of Shame").withFont(.headingMedium).foregroundColor(.secondaryLabel)
                HStack(spacing: TrackingMenuUX.hallOfShameRowSpacing) {
                    ForEach(hallOfShameDomains, id: \.domain.rawValue) { hallOfShameDomain in
                        HallOfShameElement(hallOfShameDomain: hallOfShameDomain)
                    }
                }.padding(.bottom, 4)
            }.padding(.vertical, 14)
        }
    }
}

struct TrackingMenuView: View {
    @EnvironmentObject var viewModel: TrackingStatsViewModel

    @State private var isShowingPopup = false

    var body: some View {
        GroupedStack {
            if viewModel.preventTrackersForCurrentPage {
                HStack(spacing: 8) {
                    TrackingMenuFirstRowElement(label: "Trackers", num: viewModel.numTrackers)
                    TrackingMenuFirstRowElement(label: "Domains", num: viewModel.numDomains)
                }
                if !viewModel.hallOfShameDomains.isEmpty {
                    HallOfShameView(hallOfShameDomains: viewModel.hallOfShameDomains)
                }
            }

            TrackingMenuProtectionRowButton(
                preventTrackers: $viewModel.preventTrackersForCurrentPage)

            if FeatureFlag[.newTrackingProtectionSettings] {
                GroupedCellButton(action: { isShowingPopup = true }) {
                    HStack {
                        Text("Advanced Privacy Settings").withFont(.bodyLarge)
                        Spacer()
                        Symbol(decorative: .shieldLefthalfFill)
                    }.foregroundColor(.label)
                }
                .sheet(isPresented: $isShowingPopup) {
                    TrackingMenuSettingsView(domain: "example.com")
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            viewModel.viewVisible = true
            self.viewModel.refreshStats()
        }
        .onDisappear {
            viewModel.viewVisible = false
        }
    }
}
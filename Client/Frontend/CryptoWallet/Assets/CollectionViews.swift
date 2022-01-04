// Copyright Neeva. All rights reserved.

import Foundation
import SDWebImageSwiftUI
import Shared
import SwiftUI

struct CollectionStatView: View {
    let statName: String
    let statAmount: String
    let inEth: Bool

    var body: some View {
        VStack(spacing: 6) {
            if inEth {
                HStack(spacing: 0) {
                    Image("ethLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                    Text(statAmount)
                        .withFont(.headingXLarge)
                        .foregroundColor(.label)
                }
            } else {
                Text(statAmount)
                    .withFont(.headingXLarge)
                    .foregroundColor(.label)
            }
            Text(statName)
                .withFont(.headingXSmall)
                .foregroundColor(.label)
        }
    }
}

enum CollectionStatsWindow: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case overall = "All"

    var id: String { self.rawValue }

    func volume(from stats: CollectionStats) -> String {
        switch self {
        case .today:
            return String(format: "%.1f", stats.oneDayVolume)
        case .week:
            return String(format: "%.1f", stats.weekVolume / 1000) + "K"
        case .month:
            return String(format: "%.1f", stats.monthVolume / 1000) + "K"
        case .overall:
            return String(format: "%.1f", stats.overallVolume / 1000) + "K"
        }
    }

    func averagePrice(from stats: CollectionStats) -> String {
        switch self {
        case .today:
            return String(format: "%.2f", stats.oneDayAveragePrice)
        case .week:
            return String(format: "%.2f", stats.weekAveragePrice)
        case .month:
            return String(format: "%.2f", stats.monthAveragePrice)
        case .overall:
            return String(format: "%.2f", stats.overallAveragePrice)
        }
    }

    func sales(from stats: CollectionStats) -> String {
        switch self {
        case .today:
            return String(format: "%.f", stats.oneDaySales)
        case .week:
            return String(format: "%.1f", stats.weekSales / 1000) + "K"
        case .month:
            return String(format: "%.1f", stats.monthSales / 1000) + "K"
        case .overall:
            return String(format: "%.1f", stats.overallSales / 1000) + "K"
        }
    }
}

struct CollectionWindowStatsView: View {
    @State var window = CollectionStatsWindow.overall
    let stats: CollectionStats

    var body: some View {
        VStack {
            HStack(spacing: 16) {
                Menu(
                    content: {
                        ForEach(CollectionStatsWindow.allCases) { win in
                            Button(
                                action: {
                                    window = win
                                },
                                label: {
                                    Text(win.rawValue.capitalized)
                                        .withFont(.headingXSmall)
                                })
                        }
                    },
                    label: {
                        VStack(spacing: 6) {
                            Symbol(decorative: .calendar, style: .headingXLarge)
                                .foregroundColor(.label)
                            HStack {
                                Text(window.rawValue.capitalized)
                                    .withFont(.headingXSmall)
                                    .foregroundColor(.label)
                                Symbol(decorative: .arrowtriangleDownFill, style: .headingXSmall)
                                    .foregroundColor(.label)
                            }
                        }
                    })
                CollectionStatView(
                    statName: "VOLUME", statAmount: window.volume(from: stats), inEth: true)
                CollectionStatView(
                    statName: "SALES", statAmount: window.sales(from: stats), inEth: false)
                CollectionStatView(
                    statName: "AVG PRICE", statAmount: window.averagePrice(from: stats),
                    inEth: true)
            }
        }
    }
}

struct CollectionStatsView: View {
    let stats: CollectionStats
    var verified: Bool = false

    var body: some View {
        VStack {
            HStack(spacing: 16) {
                if verified {
                    Image("twitter-verified")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                CollectionStatView(
                    statName: "COUNT", statAmount: String(stats.count),
                    inEth: false)
                CollectionStatView(
                    statName: "FLOOR",
                    statAmount: String(format: "%.2f", stats.floorPrice ?? 0),
                    inEth: true)
            }
            CollectionWindowStatsView(stats: stats)
        }
    }
}

struct CollectionView: View {
    let collection: Collection

    var body: some View {
        VStack(spacing: 4) {
            WebImage(url: collection.bannerImageURL)
                .placeholder {
                    Color.TrayBackground
                }
                .resizable()
                .scaledToFill()
                .frame(maxHeight: 128)
            WebImage(url: collection.imageURL)
                .placeholder {
                    Color.TrayBackground
                }
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .roundedOuterBorder(cornerRadius: 24, color: .white, lineWidth: 2)
                .offset(y: -28)
            Text(collection.name)
                .withFont(.headingXLarge)
                .foregroundColor(.label)
            if let stats = collection.stats {
                CollectionStatsView(
                    stats: stats,
                    verified: collection.safelistRequestStatus == .verified)
            }
            Image("open-sea-badge")
                .resizable()
                .scaledToFit()
                .frame(height: 18)
                .padding(.vertical, 20)
        }
    }
}
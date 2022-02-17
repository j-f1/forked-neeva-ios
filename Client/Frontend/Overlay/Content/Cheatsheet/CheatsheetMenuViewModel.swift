// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Foundation
import Shared
import SwiftUI

public class CheatsheetMenuViewModel: ObservableObject {
    @Published private(set) var cheatsheetInfo: CheatsheetQueryController.CheatsheetInfo?
    @Published private(set) var searchRichResults: [SearchController.RichResult]?
    @Published private(set) var currentPageURL: URL?
    @Published private(set) var cheatsheetDataLoading: Bool
    @Published private(set) var currentCheatsheetQuery: String?
    @Published private(set) var cheatsheetDataError: Error?
    @Published private(set) var searchRichResultsError: Error?

    var cheatSheetIsEmpty: Bool {
        if let cheatsheetInfo = cheatsheetInfo {
            if let recipe = cheatsheetInfo.recipe {
                // recipeView
                if let ingredients = recipe.ingredients,
                    let instructions = recipe.instructions,
                    ingredients.count > 0,
                    instructions.count > 0
                {
                    return false
                }
            }
            // priceHistorySection
            if let priceHistory = cheatsheetInfo.priceHistory,
                priceHistory.Max.Price.isEmpty || !priceHistory.Min.Price.isEmpty
            {
                return false
            }
            // reviewURLSection
            if cheatsheetInfo.reviewURL?.count ?? 0 > 0 {
                return false
            }
            // memorizedQuerySection
            if cheatsheetInfo.memorizedQuery?.count ?? 0 > 0 {
                return false
            }
        }
        // renderRichResult views
        if let searchRichResults = searchRichResults,
            !searchRichResults.isEmpty
        {
            return false
        }
        return true
    }

    var currentCheatsheetQueryAsURL: URL? {
        guard let query = currentCheatsheetQuery,
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed),
            !encodedQuery.isEmpty
        else {
            return nil
        }
        return URL(string: "\(NeevaConstants.appSearchURL)?q=\(encodedQuery)")
    }

    var reload: () -> Void

    private var subscriptions: Set<AnyCancellable> = []

    var loggerAttributes: [ClientLogCounterAttribute] {
        [
            ClientLogCounterAttribute(
                key: LogConfig.CheatsheetAttribute.currentPageURL,
                value: currentPageURL?.absoluteString
            ),
            ClientLogCounterAttribute(
                key: LogConfig.CheatsheetAttribute.currentCheatsheetQuery,
                value: currentCheatsheetQuery
            ),
        ]
    }

    init(tabManager: TabManager) {
        self.cheatsheetInfo = tabManager.selectedTab?.cheatsheetData
        self.searchRichResults = tabManager.selectedTab?.searchRichResults
        self.currentPageURL = tabManager.selectedTab?.webView?.url
        self.cheatsheetDataLoading = tabManager.selectedTab?.cheatsheetDataLoading ?? false
        self.currentCheatsheetQuery = tabManager.selectedTab?.currentCheatsheetQuery
        self.reload = { tabManager.selectedTab?.fetchCheatsheetInfo() }

        tabManager.selectedTab?.$cheatsheetDataLoading.assign(to: \.cheatsheetDataLoading, on: self)
            .store(in: &subscriptions)

        tabManager.selectedTab?.$currentCheatsheetQuery.assign(
            to: \.currentCheatsheetQuery, on: self
        )
        .store(in: &subscriptions)

        tabManager.selectedTab?.$cheatsheetData.assign(to: \.cheatsheetInfo, on: self).store(
            in: &subscriptions)

        tabManager.selectedTab?.$searchRichResults.assign(to: \.searchRichResults, on: self).store(
            in: &subscriptions)

        tabManager.selectedTab?.$url.assign(to: \.currentPageURL, on: self).store(
            in: &subscriptions)

        tabManager.selectedTab?.$cheatsheetDataError
            .assign(to: \.cheatsheetDataError, on: self)
            .store(in: &subscriptions)

        tabManager.selectedTab?.$searchRichResultsError
            .assign(to: \.searchRichResultsError, on: self)
            .store(in: &subscriptions)
    }
}

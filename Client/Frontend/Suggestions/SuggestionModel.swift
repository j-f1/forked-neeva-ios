/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Storage
import XCGLogger
import Combine

private let log = Logger.browserLogger

private let URLBeforePathRegex = try! NSRegularExpression(pattern: "^https?://([^/]+)/", options: [])

/**
 * Shared data source for the SearchViewController and the URLBar domain completion.
 * Since both of these use the same SQL query, we can perform the query once and dispatch the results.
 */
class HistorySuggestionModel: ObservableObject {
    fileprivate let frecentHistory: FrecentHistory

    @Published private(set) var autocompleteSuggestion = ""
    @Published private(set) var sites: [Site]?

    private var skipNextAutocomplete = false

    init(previewLensBang: ActiveLensBangInfo?, sites: [Site]? = nil) {
        self.frecentHistory = BrowserProfile(localName: "profile").history.getFrecentHistory()
        self.activeLensBang = previewLensBang
        self.sites = sites
    }

    init(profile: Profile) {
        self.frecentHistory = profile.history.getFrecentHistory()
    }

    fileprivate lazy var topDomains: [String] = {
        let filePath = Bundle.main.path(forResource: "topdomains", ofType: "txt")
        return try! String(contentsOfFile: filePath!).components(separatedBy: "\n")
    }()

    // `weak` usage here allows deferred queue to be the owner. The deferred is always filled and this set to nil,
    // this is defensive against any changes to queue (or cancellation) behaviour in future.
    private weak var currentDeferredHistoryQuery: CancellableDeferred<Maybe<Cursor<Site>>>?

    private var searchTextSubscription: AnyCancellable?

    private func subscribe() {
        searchTextSubscription = SearchTextModel.shared.$query.withPrevious().sink { [unowned self] oldQuery, query in
            currentDeferredHistoryQuery?.cancel()

            guard let query = query else {
                sites = nil
                activeLensBang = nil
                return
            }

            if query.isEmpty {
                sites = []
                return
            }

            guard let deferredHistory = frecentHistory.getSites(matchingSearchQuery: query, limit: 100) as? CancellableDeferred else {
                assertionFailure("FrecentHistory query should be cancellable")
                return
            }

            currentDeferredHistoryQuery = deferredHistory

            deferredHistory.uponQueue(.main) { result in
                defer {
                    self.currentDeferredHistoryQuery = nil
                }

                guard !deferredHistory.cancelled else {
                    return
                }

                // Exclude Neeva search url suggestions from history suggest, since they should
                // readily be coming as query suggestions.
                let deferredHistorySites = (result.successValue?.asArray() ?? [])
                    .filter {!($0.url.hasPrefix(NeevaConstants.appSearchURL.absoluteString))}

                // Load the data in the table view.
                self.sites = deferredHistorySites

                // If the new search string is not longer than the previous
                // we don't need to find an autocomplete suggestion.
                guard (oldQuery?.count ?? 0) < query.count else {
                    return
                }

                // If we should skip the next autocomplete, reset
                // the flag and bail out here.
                guard !self.skipNextAutocomplete else {
                    self.skipNextAutocomplete = false
                    return
                }

                // First, see if the query matches any URLs from the user's search history.
                for site in deferredHistorySites {
                    if let completion = self.completionForURL(site.url, favicon: site.icon) {
                        self.autocompleteSuggestion = completion
                        return
                    }
                }

                // If there are no search history matches, try matching one of the Alexa top domains.
                for domain in self.topDomains {
                    if let completion = self.completionForDomain(domain) {
                        self.autocompleteSuggestion = completion
                        return
                    }
                }

                self.autocompleteSuggestion = ""
            }
        }
    }

    func setQueryWithoutAutocomplete(_ query: String) {
        skipNextAutocomplete = true
        SearchTextModel.shared.query = query
    }

    fileprivate func completionForURL(_ url: String, favicon: Favicon?) -> String? {
        // Extract the pre-path substring from the URL. This should be more efficient than parsing via
        // NSURL since we need to only look at the beginning of the string.
        // Note that we won't match non-HTTP(S) URLs.
        guard let match = URLBeforePathRegex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.count)) else {
            return nil
        }

        // If the pre-path component (including the scheme) starts with the query, just use it as is.
        var prePathURL = (url as NSString).substring(with: match.range(at: 0))
        if prePathURL.hasPrefix(SearchTextModel.shared.query ?? "") {
            // Trailing slashes in the autocompleteTextField cause issues with Swype keyboard. Bug 1194714
            if prePathURL.hasSuffix("/") {
                prePathURL.remove(at: prePathURL.index(before: prePathURL.endIndex))
            }
            return prePathURL
        }

        // Otherwise, find and use any matching domain.
        // To simplify the search, prepend a ".", and search the string for ".query".
        // For example, for http://en.m.wikipedia.org, domainWithDotPrefix will be ".en.m.wikipedia.org".
        // This allows us to use the "." as a separator, so we can match "en", "m", "wikipedia", and "org",
        let domain = (url as NSString).substring(with: match.range(at: 1))
        return completionForDomain(domain)
    }

    fileprivate func completionForDomain(_ domain: String) -> String? {
        let domainWithDotPrefix: String = ".\(domain)"
        if let range = domainWithDotPrefix.range(of: ".\(SearchTextModel.shared.query ?? "")", options: .caseInsensitive, range: nil, locale: nil) {
            // We don't actually want to match the top-level domain ("com", "org", etc.) by itself, so
            // so make sure the result includes at least one ".".
            let matchedDomain = String(domainWithDotPrefix[domainWithDotPrefix.index(range.lowerBound, offsetBy: 1)...])
            if matchedDomain.contains(".") {
                return matchedDomain
            }
        }

        return nil
    }
}
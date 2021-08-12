// Copyright Neeva. All rights reserved.

import Shared
import Storage
import SwiftUI

private enum LocationTextFieldIconUX {
    static let size: CGFloat = 16
    static let faviconSize: CGFloat = 14
}

/// The icon displayed next to the location text field
struct LocationTextFieldIcon: View {
    let currentUrl: URL?

    @EnvironmentObject private var searchQuery: SearchQueryModel
    @EnvironmentObject private var suggestionModel: SuggestionModel

    var body: some View {
        Group {
            let completion = suggestionModel.completion.map { searchQuery.value + $0 }

            if let type = suggestionModel.activeLensBang?.type {
                Image(systemSymbol: type.defaultSymbol)
            } else if let completion = completion,
                let url = completion.contains("://")
                    ? URL(string: completion) : URL(string: "https://\(completion)")
            {
                FaviconView(
                    url: url, size: LocationTextFieldIconUX.faviconSize, bordered: false,
                    defaultBackground: .clear
                )
                .cornerRadius(4)
            } else if searchQuery.value.looksLikeAURL,
                let url = searchQuery.value.contains("://")
                    ? URL(string: searchQuery.value) : URL(string: "https://\(searchQuery.value)")
            {
                FaviconView(
                    url: url, size: LocationTextFieldIconUX.faviconSize, bordered: false,
                    defaultBackground: .clear
                )
                .cornerRadius(4)
            } else {
                Image("neevaMenuIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: LocationTextFieldIconUX.size, height: LocationTextFieldIconUX.size)
        .frame(width: TabLocationViewUX.height)
        .transition(.identity)
    }
}

struct LocationTextFieldIcon_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LocationTextFieldIcon(currentUrl: nil)
                .previewDisplayName("Empty")

            HStack(spacing: 0) {
                LocationTextFieldIcon(currentUrl: nil)
                    .environmentObject(SuggestionModel())
                LocationTextFieldIcon(currentUrl: nil)
                    .environmentObject(SuggestionModel())
            }.previewDisplayName("Lens/Bang")

            HStack(spacing: 0) {
                LocationTextFieldIcon(currentUrl: nil)
                    .environmentObject(SuggestionModel(previewCompletion: "example.com"))
                LocationTextFieldIcon(currentUrl: nil)
                    .environmentObject(SuggestionModel(previewCompletion: "apple.com"))
            }.previewDisplayName("Domain completion")

            HStack(spacing: 0) {
                LocationTextFieldIcon(currentUrl: nil)
                    .environmentObject(SearchQueryModel(previewValue: "https://example.com"))
                LocationTextFieldIcon(currentUrl: nil)
                    .environmentObject(SearchQueryModel(previewValue: "https://apple.com"))
            }.previewDisplayName("Entered URL")

            LocationTextFieldIcon(currentUrl: nil)
                .environmentObject(SearchQueryModel(previewValue: "https://github.com projects"))
                .previewDisplayName("Entered Query")
        }
        .frame(height: TabLocationViewUX.height)
        .background(
            Capsule()
                .fill(Color.systemFill)
        )
        .padding()
        .previewLayout(.sizeThatFits)
        .environmentObject(SearchQueryModel(previewValue: ""))
        .environmentObject(SuggestionModel(previewSites: []))
    }
}

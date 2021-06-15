// Copyright Neeva. All rights reserved.

import SwiftUI
import Shared

struct LocationLabel: View {
    let url: URL?
    let isSecure: Bool
    
    var body: some View {
        if let url = url, let internalURL = InternalURL(url), internalURL.isAboutHomeURL {
            TabLocationViewUX.placeholder.foregroundColor(.secondaryLabel)
        } else if let query = neevaSearchEngine.queryForLocationBar(from: url) {
            Label { Text(query) } icon: { Symbol(.magnifyingglass) }
        } else if let scheme = url?.scheme, let host = url?.host, (scheme == "https" || scheme == "http") {
            // NOTE: Punycode support was removed
            let host = Text(host).truncationMode(.head)
            if isSecure {
                Label {
                    host
                } icon: {
                    Symbol(.lockFill)
                }
            } else {
                host
            }
        } else if let url = url {
            Text(url.absoluteString)
        } else {
            TabLocationViewUX.placeholder.foregroundColor(.secondaryLabel)
        }
    }
}

struct LocationLabel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LocationLabel(url: URL(string: "http://vviii.verylong.subdomain.neeva.com"), isSecure: false)
            LocationLabel(url: URL(string: "https://neeva.com/asdf"), isSecure: true)
            LocationLabel(url: neevaSearchEngine.searchURLForQuery("a long search query with words"), isSecure: false)
            LocationLabel(url: URL(string: "ftp://someftpsite.com/dir/file.txt"), isSecure: false)
        }.padding().previewLayout(.sizeThatFits)
    }
}
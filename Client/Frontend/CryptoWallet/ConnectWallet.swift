// Copyright Neeva. All rights reserved.

import Foundation
import Shared
import SwiftUI

public class WalletConnectDetector: ObservableObject {
    public static let WalletRegistryURL = URL(
        string: "http://registry.walletconnect.org/data/wallets.json")!
    public static let scrapeWalletConnectURI = """
        let url = new URL(Array.prototype.map.call(document.querySelectorAll('a.walletconnect-connect__button__icon_anchor'), function links(element) {var link=element["href"]; return link})[0]); let uri; if(url.pathname == '/wc') { uri = new URL(url.searchParams.get("uri")) }; let output; if (uri.protocol == 'wc:') { output = uri.toString()}
        """
    public static var shared = WalletConnectDetector()

    @Published var walletConnectURL: URL? = nil
}

struct ConnectWalletPanel: View {
    @EnvironmentObject var web3Model: Web3Model

    var body: some View {
        VStack(spacing: 16) {
            Button(
                action: {
                    guard let connectToURI = web3Model.wcURL else { return }

                    DispatchQueue.global(qos: .userInitiated).async {
                        try? web3Model.server?.connect(to: connectToURI)
                    }
                    withAnimation {
                        web3Model.wcURL = nil
                    }
                },
                label: {
                    Text("Connect Neeva Wallet")
                        .frame(maxWidth: .infinity)
                }
            ).buttonStyle(NeevaButtonStyle(.primary))
            if let collection = web3Model.matchingCollection {
                CollectionView(collection: collection)
            }
        }
        .padding(12)
        .background(Color.DefaultBackground)
        .cornerRadius(12, corners: [.topLeading, .topTrailing])
    }
}
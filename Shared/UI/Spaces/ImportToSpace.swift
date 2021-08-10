// Copyright Neeva. All rights reserved.

import Apollo
import Foundation

struct SpaceLinkData {
    let title: String
    let url: URL
}

public enum SpaceImportDomain: String {
    case linkinbio = "linkin.bio"
    case linktree = "linktr.ee"
    case likeshop = "likeshop.me"
    case lnkbio = "lnk.bio"

    public var script: String {
        switch self {
        case .linkinbio:
            return "Array.prototype.map.call(document.querySelectorAll('a.o--card'), function links(element) {var image=element.querySelector('img'); return [image ? image['alt'].substring(0, image['alt'].indexOf('.')+1) : '', element['href']]})"
        case .linktree:
            return "Array.prototype.map.call(document.querySelectorAll('a[data-testid=LinkButton]'), element => [element.querySelector('p').innerHTML, element['href']])"
        case .likeshop:
            return "Array.prototype.map.call(document.querySelectorAll('a.media-link'), element => [element.querySelector('img') ? element.querySelector('img')['alt'] : '', element['href']])"
        case .lnkbio:
            return "Array.prototype.map.call(document.querySelectorAll('a[class*=pb-linktitle]'), element => [element.innerHTML, unescape(element['href'].substring(21))])"
        }
    }
}

public class SpaceImportHandler {
    let title: String
    var data: [SpaceLinkData]
    public var completion: (() -> Void)? = nil
    public var spaceURL: URL {
        guard let id = spaceID else {
            return NeevaConstants.appSpacesURL
        }

        return NeevaConstants.appSpacesURL / id
    }

    private var cancellable: Cancellable? = nil
    private var spaceID: String? = nil

    public init(title: String, data: [[String]]) {
        self.data = data.map {
            assert($0.count == 2)
            return SpaceLinkData(title: $0[0], url: URL(string: $0[1])!)
        }
        self.title = title
    }

    func importToNewSpace() {
        createSpace()
    }

    private func createSpace() {
        self.cancellable = CreateSpaceMutation(
            name: title
        ).perform { result in
            self.cancellable = nil
            switch result {
            case .success(let data):
                self.spaceID = data.createSpace
                self.addNext()
            case .failure(_):
                self.completion?()
            }
        }
    }

    private func addNext() {
        guard let linkData = data.popLast() else {
            completion?()
            return
        }
        self.cancellable = AddToSpaceMutation(
            input: AddSpaceResultByURLInput(
                spaceId: spaceID!,
                url: linkData.url.absoluteString,
                title: linkData.title.isEmpty ? title : linkData.title,
                data: "",
                mediaType: "text/plain",
                isBase64: false,
                snapshotExpected: false
            )
        ).perform { result in
            self.cancellable = nil
            switch result {
            case .failure(_):
                self.completion?()
                break
            case .success(_):
                self.addNext()
            }
        }
    }
}
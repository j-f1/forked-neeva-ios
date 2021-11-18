// Copyright Neeva. All rights reserved.

import SDWebImageSwiftUI
import Shared
import SwiftUI

enum AddOrUpdateSpaceConfig {
    case addSpaceItem
    case updateSpaceItem(String)
    case updateSpace
}

struct AddOrUpdateSpaceContent: View {
    @Environment(\.hideOverlay) private var hideOverlay

    let space: Space
    let config: AddOrUpdateSpaceConfig

    var title: String {
        switch config {
        case .addSpaceItem:
            return "Add item"
        case .updateSpaceItem(let _):
            return "Edit item"
        case .updateSpace:
            return "Update Space"
        }
    }

    init(space: Space, config: AddOrUpdateSpaceConfig) {
        self.space = space
        self.config = config
    }

    var body: some View {
        AddOrUpdateSpaceView(space: space, config: config, dismiss: hideOverlay)
            .overlayIsFixedHeight(isFixedHeight: true)
            .overlayTitle(title: title)
    }
}

private enum FieldType: String, Hashable {
    case urlField = "URL"
    case titleField = "TITLE"
    case descriptionField = "DESCRIPTION"
}

@available(iOS 15.0, *)
private struct iOS15InputField: View {
    @FocusState private var isFocused: FieldType?

    let title: FieldType
    let bodyText: String
    @Binding var inputText: String

    private func textEditAccentColor(type: FieldType) -> Color {
        if type == isFocused {
            return .ui.adaptive.blue
        } else {
            return .quaternaryLabel
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.rawValue)
                .withFont(.headingXSmall)
                .foregroundColor(.secondaryLabel)

            if case .descriptionField = title {
                TextEditor(text: $inputText)
                    .withFont(unkerned: .bodyLarge)
                    .frame(
                        maxWidth: .infinity, minHeight: 80,
                        maxHeight: isFocused == title ? .infinity : 110
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($isFocused, equals: title)
                    .accentColor(textEditAccentColor(type: title))
                    .animation(.easeInOut)
            } else {
                TextField(bodyText, text: $inputText)
                    .withFont(unkerned: .bodyLarge)
                    .autocapitalization(title == .titleField ? .words : .none)
                    .disableAutocorrection(true)
                    .focused($isFocused, equals: title)
                    .accentColor(textEditAccentColor(type: title))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .roundedOuterBorder(cornerRadius: 12, color: textEditAccentColor(type: title), lineWidth: 1)
    }
}

private struct LegacyInputField: View {
    let title: FieldType
    let bodyText: String
    @Binding var inputText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.rawValue)
                .withFont(.headingXSmall)
                .foregroundColor(.secondaryLabel)

            if case .descriptionField = title {
                TextEditor(text: $inputText)
                    .withFont(unkerned: .bodyLarge)
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 110)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField(bodyText, text: $inputText)
                    .withFont(unkerned: .bodyLarge)
                    .autocapitalization(title == .titleField ? .words : .none)
                    .disableAutocorrection(title != .titleField)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .roundedOuterBorder(cornerRadius: 12, color: .quaternaryLabel, lineWidth: 1)
    }
}

struct AddOrUpdateSpaceView: View {
    let space: Space
    let config: AddOrUpdateSpaceConfig
    let dismiss: () -> Void
    let thumbnailModel = CustomThumbnailModel()

    @EnvironmentObject var spaceModel: SpaceCardModel
    @State var descriptionText: String
    @State var titleText: String
    @State var urlText: String

    var shouldShowURL: Bool {
        guard case .addSpaceItem = config else {
            return false
        }
        return true
    }

    init(space: Space, config: AddOrUpdateSpaceConfig, dismiss: @escaping () -> Void) {
        self.space = space
        self.config = config
        self.dismiss = dismiss

        switch config {
        case .addSpaceItem:
            self.titleText = ""
            self.urlText = ""
            self.descriptionText = ""
        case .updateSpaceItem(let entityID):
            let data = space.contentData?.first(where: { $0.id == entityID })
            self.titleText = data?.title ?? ""
            self.urlText = data?.url?.absoluteString ?? ""
            self.descriptionText = data?.snippet ?? ""
        case .updateSpace:
            self.titleText = space.name
            self.urlText = ""
            self.descriptionText = space.description ?? ""
        }
    }

    private func inputField(title: FieldType, bodyText: String, inputText: Binding<String>)
        -> some View
    {
        Group {
            if #available(iOS 15.0, *) {
                iOS15InputField(title: title, bodyText: bodyText, inputText: inputText)
            } else {
                LegacyInputField(title: title, bodyText: bodyText, inputText: inputText)
            }
        }
    }

    var body: some View {
        GroupedStack {
            inputField(
                title: .titleField, bodyText: "Please provide a title", inputText: $titleText)
            inputField(
                title: .descriptionField,
                bodyText: "Please provide a description",
                inputText: $descriptionText)
            if let url = URL(string: urlText),
                let thumbnails = spaceModel.thumbnailURLCandidates[url],
                thumbnailModel.showing
            {
                CustomThumbnailPicker(thumbnails: thumbnails, model: thumbnailModel)
            } else if case .updateSpace = config, let details = spaceModel.detailedSpace {
                SpaceThumbnailPicker(spaceDetails: details, model: thumbnailModel)
            }
            if shouldShowURL {
                inputField(
                    title: .urlField, bodyText: "Add a URL to your new item (optional)",
                    inputText: $urlText
                )
            }
            Button(
                action: {
                    switch config {
                    case .addSpaceItem:
                        let data = SpaceEntityData(
                            id: space.id.id,
                            url: URL(string: urlText),
                            title: titleText,
                            snippet: descriptionText,
                            thumbnail: nil,
                            previewEntity: .webPage)

                        // modify target spaceCardDetail's Data and signal changes
                        spaceModel.detailedSpace?.space?.contentData?.insert(data, at: 0)
                        spaceModel.detailedSpace?.updateDetails()
                        spaceModel.add(
                            spaceID: space.id.id, url: urlText,
                            title: titleText, description: descriptionText)
                    case .updateSpaceItem(let entityID):
                        let oldData = (space.contentData?.first(where: { $0.id == entityID }))!
                        let index = (space.contentData?.firstIndex(where: { $0.id == entityID }))!
                        let newData = SpaceEntityData(
                            id: oldData.id,
                            url: oldData.url,
                            title: titleText,
                            snippet: descriptionText,
                            thumbnail: thumbnailModel.selectedData ?? oldData.thumbnail,
                            previewEntity: oldData.previewEntity)
                        spaceModel.detailedSpace?.space?.contentData?.replaceSubrange(
                            index..<(index + 1), with: [newData])
                        spaceModel.detailedSpace?.allDetails.replaceSubrange(
                            index..<(index + 1),
                            with: [SpaceEntityThumbnail(data: newData, spaceID: space.id.id)])
                        spaceModel.updateSpaceEntity(
                            spaceID: space.id.id, entityID: entityID,
                            title: titleText, snippet: descriptionText,
                            thumbnail: thumbnailModel.selectedData)
                        thumbnailModel.selectedData = nil
                        thumbnailModel.thumbnailData = [URL: String]()
                    case .updateSpace:
                        var thumbnail: String? = nil
                        if let id = thumbnailModel.selectedSpaceThumbnailEntityID {
                            thumbnail = space.contentData?.first(where: { $0.id == id })?.thumbnail
                        } else if let thumbnailData = thumbnailModel.selectedData {
                            thumbnail = thumbnailData
                        }
                        spaceModel.updateSpaceHeader(
                            space: space, title: titleText,
                            description: descriptionText, thumbnail: thumbnail)
                    }
                    dismiss()
                },
                label: {
                    Text("Save")
                        .withFont(.labelLarge)
                        .frame(maxWidth: .infinity)
                        .clipShape(Capsule())
                }
            )
            .buttonStyle(NeevaButtonStyle(.primary))
            .padding(.vertical, 16)
        }.onAppear {
            thumbnailModel.showing = true
        }.onDisappear {
            thumbnailModel.showing = false
        }
    }
}
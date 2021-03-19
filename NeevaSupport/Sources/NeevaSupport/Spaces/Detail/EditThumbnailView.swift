//
//  EditThumbnailView.swift
//  
//
//  Created by Jed Fox on 1/5/21.
//

import SwiftUI

// TODO: fix accessibility
/// Displays a scrollable list of suggested thumbnails for the given entity.
struct EditThumbnailView: View {
    @Binding var selectedThumbnail: String
    @StateObject var controller: EntityThumbnailController

    /// - Parameters:
    ///   - spaceId: The ID of the space the entity is inside
    ///   - entityId: The ID of the entity we’re editing
    ///   - selectedThumbnail: a binding to the `data:` URL of the thumbnail
    init(spaceId: String, entityId: String, selectedThumbnail: Binding<String>) {
        _controller = .init(wrappedValue: EntityThumbnailController(spaceId: spaceId, entityId: entityId))
        _selectedThumbnail = selectedThumbnail
    }
    var body: some View {
        switch controller.state {
        case .failure(let error):
            ErrorView(error, in: self, tryAgain: { controller.reload() })
                .buttonStyle(BorderlessButtonStyle())
        case .success(let images):
            if images.isEmpty {
                HStack {
                    Spacer()
                    Text("No thumbnails found.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ThumbnailList {
                    ForEach(images) { image in
                        if let thumbnail = image.thumbnail,
                           let dataURIBody = thumbnail.dataURIBody,
                           let uiImage = UIImage(data: dataURIBody) {
                            Button {
                                selectedThumbnail = thumbnail
                            } label: {
                                ThumbnailImage(
                                    image: Image(uiImage: uiImage).resizable(),
                                    isSelected: thumbnail == selectedThumbnail
                                )
                            }
                        }
                    }
                }
            }
        case .running:
            ThumbnailList {
                ForEach(0..<10) { _ in
                    ThumbnailImage(
                        image: ThumbnailPlaceholder(),
                        isSelected: false
                    )
                }
            }.disabled(true)
        }
    }
}

fileprivate struct ThumbnailList<Content: View>: View {
    let content: () -> Content
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12, content: content).padding()
        }.padding(.horizontal, -20)
    }
}

/// A looping animated gradient displayed while thumbnails are loading
fileprivate struct ThumbnailPlaceholder: View {
    @State private var offset: CGFloat = -1
    @Namespace private var namespace
    var body: some View {
        GeometryReader { geom in
            HStack(spacing: 0) {
                let gradient = LinearGradient(gradient: .skeleton, startPoint: .leading, endPoint: .trailing)
                    .frame(width: geom.size.width)
                gradient
                gradient.scaleEffect(x: -1, y: 1, anchor: .center)
                gradient
            }
            .offset(x: offset * geom.size.width)
            .frame(width: geom.size.width)
            .onAppear {
                withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                    offset = 1
                }
            }
        }
    }
}

/// Clips the provided `image` to a rounded rectangle and overlays a selection indicator if `isSelected` is true
struct ThumbnailImage<Content: View>: View {
    let image: Content
    let isSelected: Bool
    var body: some View {
        let thumbnailImage = image
            .aspectRatio(contentMode: .fill)
            .frame(width: 95, height: 85)
            .cornerRadius(6)
        if isSelected {
            thumbnailImage
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 5)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .font(Font.title.bold())
                        .frame(width: 20, height: 20)
                        .padding(7)
                        .background(
                            Circle()
                                .fill(Color.accentColor)
                        )
                ).accessibilityAddTraits(.isSelected)
        } else {
            thumbnailImage
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}

struct EditThumbnailView_Previews: PreviewProvider {
    struct TestView: View {
        @State var selectedThumbnail = ""
        var body: some View {
            Form {
                Section {
                    ThumbnailList {
                        ForEach(0..<10) { _ in
                            ThumbnailImage(
                                image: ThumbnailPlaceholder(),
                                isSelected: false
                            )
                        }
                    }
                }
                EditThumbnailView(spaceId: "SkksIM_iAclak16nHYfcqAY8IwxsasTD1pU1XqUe", entityId: "0x1d170643a0684be5", selectedThumbnail: .constant(testSpace.thumbnail!))
            }
        }
    }
    static var previews: some View {
        HStack {
            let image = Image(uiImage: UIImage(data: SpaceThumbnails.githubThumbnail.dataURIBody!)!).resizable()
            ThumbnailImage(image: image, isSelected: false)
            ThumbnailImage(image: image, isSelected: true)
            ThumbnailImage(
                image: ThumbnailPlaceholder(),
                isSelected: false
            )
        }
        ThumbnailPlaceholder()
            .border(Color.red)
            .frame(width: 95, height: 85)
            .previewLayout(.sizeThatFits)
        TestView()
    }
}
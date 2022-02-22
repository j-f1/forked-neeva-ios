// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Shared
import SwiftUI

struct PopoverView<Content: View>: View {
    @State private var title: LocalizedStringKey? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let style: OverlayStyle
    let onDismiss: () -> Void
    let headerButton: OverlayHeaderButton?
    let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The semi-transparent backdrop used to shade the content that lies below
                // the sheet.
                Button(action: style.nonDismissible ? {} : onDismiss) {
                    Color.black
                        .opacity(0.2)
                        .ignoresSafeArea()
                }
                .buttonStyle(.highlightless)
                .accessibilityHint("Dismiss pop-up window")
                // make this the last option. This will bring the user’s focus first to the
                // useful content inside of the overlay sheet rather than the close button.
                .accessibilitySortPriority(-1)

                VStack {
                    if let headerButton = headerButton {
                        HStack(spacing: 0) {
                            Spacer().layoutPriority(0.5)
                            Button(
                                action: {
                                    headerButton.action()
                                    onDismiss()
                                },
                                label: {
                                    HStack(spacing: 10) {
                                        Text(headerButton.text)
                                            .withFont(.labelLarge)
                                        Symbol(decorative: headerButton.icon)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            )
                            .buttonStyle(.neeva(.primary))
                            .layoutPriority(0.5)
                        }
                    }

                    VStack {
                        if style.showTitle, let title = title {
                            HStack(spacing: 0) {
                                Text(title)
                                    .withFont(.headingXLarge)
                                    .foregroundColor(.label)
                                    .padding(.leading, 16)

                                Spacer()

                                Button(action: onDismiss) {
                                    Symbol(.xmark, style: .headingXLarge, label: "Close")
                                        .foregroundColor(.tertiaryLabel)
                                        .tapTargetFrame()
                                        .padding(.trailing, 4.5)
                                }
                            }.padding(.top)
                        }

                        ScrollView(.vertical, showsIndicators: false) {
                            content()
                                .onPreferenceChange(OverlayTitlePreferenceKey.self) {
                                    self.title = $0
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .background(
                        Color(style.backgroundColor)
                            .cornerRadius(16)
                    )
                    // 50 is button height + VStack padding
                    .frame(maxHeight: geo.size.height - paddingForSizeClass(verticalSizeClass) - 60)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, paddingForSizeClass(horizontalSizeClass))
                .padding(.vertical, paddingForSizeClass(verticalSizeClass))
            }
            .accessibilityAction(.escape, onDismiss)
        }
    }

    func paddingForSizeClass(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let defaultValue: CGFloat = 12

        guard let sizeClass = sizeClass else {
            return defaultValue
        }

        switch sizeClass {
        case .compact:
            return defaultValue
        case .regular:
            return 50
        @unknown default:
            return defaultValue
        }
    }
}

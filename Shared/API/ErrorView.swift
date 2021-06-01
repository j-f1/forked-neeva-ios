// Copyright Neeva. All rights reserved.

import SwiftUI

struct BigBlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.vertical, 7)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.5 : 1)
                    .frame(minWidth: 230)
            )
    }
}

/// A view that displays an `Error`
public struct ErrorView: View {
    let error: Error
    let tryAgain: (() -> ())?
    let viewName: String

    /// - Parameters:
    ///   - error: The error to display.
    ///   - in: Pass `self` to provide the name of your view in any feedback the user sends from this screen.
    ///   - tryAgain: If provided, a “Reload” button will be displayed. Tapping the button will call this closure.
    public init<T: View>(_ error: Error, in _: T, tryAgain: (() -> ())? = nil) {
        self.error = error
        self.tryAgain = tryAgain
        self.viewName = "\(T.self)"
    }

    /// - Parameters:
    ///   - error: The error to display.
    ///   - viewName: The name of the view to include in any feedback the user sends from this screen.
    ///   - tryAgain: If provided, a “Reload” button will be displayed. Tapping the button will call this closure.
    public init(_ error: Error, viewName: String, tryAgain: (() -> ())? = nil) {
        self.error = error
        self.tryAgain = tryAgain
        self.viewName = viewName
    }

    @ObservedObject private var reachability = NetworkReachability.shared
    @State private var sendingFeedback = false

    var gqlErrors: [String]? {
        (error as? GraphQLAPI.Error)?.errors.compactMap(\.message)
    }

    var isLoginError: Bool {
        guard let first = gqlErrors?.first, gqlErrors?.count == 1 else { return false }
        return first == "login required to access this field"
    }

    public var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                if isLoginError {
                    LoginView()
                } else if let isOnline = reachability.isOnline, !isOnline {
                    OfflineView()
                } else {
                    GenericErrorView(viewName: viewName, error: error, gqlErrors: gqlErrors)
                }
                if let tryAgain = tryAgain, !isLoginError {
                    Button(action: tryAgain) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .font(Font.footnote.bold())
                    .padding(.vertical)
                }
                Spacer()
            }.onChange(of: reachability.isOnline) { nowOnline in
                if nowOnline == true {
                    tryAgain?()
                }
            }
            Spacer()
        }
    }
}

/// Displays a generic “Error” screen. Used as a fallback if we don’t have special display for the error message.
fileprivate struct GenericErrorView: View {
    let viewName: String
    let error: Error
    let gqlErrors: [String]?

    @State private var sendingFeedback = false

    var errorsForFeedback: String {
        if let errors = gqlErrors {
            return "• \(errors.joined(separator: "\n• "))"
        }
        return error.localizedDescription
    }

    var body: some View {
        VStack(spacing: 20) {
            Label("Error", systemImage: "exclamationmark.octagon.fill")
            .font(Font.title.bold())
            .foregroundColor(.red)
            GroupBox {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        if let errors = gqlErrors {
                            ForEach(errors, id: \.self) { error in
                                Text(error)
                            }
                        } else {
                            Text(error.localizedDescription)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                }.frame(maxHeight: 130)
            }.padding()
            // TODO: proper screenshot?
            Button(action: { sendingFeedback = true }) {
                Label("Send Feedback", systemSymbol: .bubbleLeftFill)
            }.sheet(isPresented: $sendingFeedback) {
                SendFeedbackView(screenshot: nil, initialText: "\n\nReceived these errors in \(viewName):\n\(errorsForFeedback)").font(.body)
            }
        }
    }
}

/// Prompts the user to log into Neeva
fileprivate struct LoginView: View {
    @Environment(\.onOpenURL) var onOpenURL

    var body: some View {
        VStack(spacing: 50) {
            Image.neevaLogo
            VStack(spacing: 20) {
                Text("Please sign in to continue")
                    .font(.title2)
                Text("This content can only be viewed if you sign in")
                    .font(.system(size: 15))
            }
            Button("Sign in to Neeva") { onOpenURL(NeevaConstants.appSigninURL) }
                .buttonStyle(BigBlueButtonStyle())
        }.multilineTextAlignment(.center).padding()
    }
}

/// Displayed when the device is offline
fileprivate struct OfflineView: View {
    var body: some View {
        VStack(spacing: 20) {
            Label("You’re offline", systemImage: "bolt.slash.fill")
                .font(Font.title.bold())
                .foregroundColor(.orange)
            Text("Connect to the Internet to view this content")
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}


struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorView(GraphQLAPI.Error([.init(["message": "login required to access this field"])]), viewName: "\(Self.self)")
        ErrorView(GraphQLAPI.Error([.init(["message": "login required to access this field"])]), viewName: "\(Self.self)", tryAgain: {})
        ErrorView(GraphQLAPI.Error(Array(repeating: .init(["message": "failed to reticulate the splines"]), count: 10)), viewName: "\(Self.self)")
        ErrorView(GraphQLAPI.Error([.init(["message": "failed to reticulate the splines"]), .init(["message": "the server room is on fire"])]), viewName: "\(Self.self)")
        ErrorView(GraphQLAPI.Error([.init(["message": "failed to reticulate the splines"]), .init(["message": "the server room is on fire"])]), viewName: "\(Self.self)", tryAgain: {})
        OfflineView()
    }
}
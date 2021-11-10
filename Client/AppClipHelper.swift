// Copyright Neeva. All rights reserved.

import Foundation

class AppClipHelper {
    static let appClipGroupId = "group.co.neeva.app.ios.browser.app-clip.login"

    static func retreiveAppClipData() -> String? {
        guard
            let appClipPath = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appClipGroupId)?.appendingPathComponent(
                    "AppClipValue")
        else {
            print("Unable to get URL to retrieve App Clip token")
            return nil
        }

        do {
            let data = try Data(contentsOf: appClipPath)
            return try JSONDecoder().decode(String.self, from: data)
        } catch {
            print("Error retriving App Clip data:", error.localizedDescription)
            return nil
        }
    }

    static func saveTokenToDevice(_ token: String?) {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appClipGroupId)?.appendingPathComponent(
                    "AppClipValue")
        else {
            print("Unable to get URL to save App Clip token")
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(token)
            try data.write(to: containerURL)
            print("Saved \(token as Any) to: \(containerURL.absoluteString)")
        } catch {
            print("Whoops, an error occured: \(error)")
        }
    }
}
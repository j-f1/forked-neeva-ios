// Copyright Neeva. All rights reserved.

import Defaults
import Foundation
import Shared
import UserNotifications
import XCGLogger

private let log = Logger.browser

public enum NotificationPermissionStatus: Int {
    case undecided = 0
    case authorized = 1
    case denied = 2
}

class NotificationPermissionHelper {
    static let shared = NotificationPermissionHelper()

    var permissionStatus: NotificationPermissionStatus {
        return NotificationPermissionStatus(rawValue: Defaults[.notificationPermissionState])
            ?? .undecided
    }

    func didAlreadyRequestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus != .notDetermined)
            }
        }
    }

    func isAuthorized(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(
                settings.authorizationStatus != .denied
                    && settings.authorizationStatus != .notDetermined)
        }
    }

    func requestPermissionIfNeeded(
        completion: ((Bool) -> Void)? = nil,
        openSettingsIfNeeded: Bool = false
    ) {
        isAuthorized { [self] authorized in
            guard !authorized else {
                completion?(true)
                return
            }

            didAlreadyRequestPermission { requested in
                if !requested {
                    ClientLogger.shared.logCounter(.ShowSystemNotificationPrompt)
                    requestPermissionFromSystem(completion: completion)
                } else if openSettingsIfNeeded {
                    /// If we can't show the iOS system notification because the user denied our first request,
                    /// this will take them to system settings to enable notifications there.
                    SystemsHelper.openSystemSettingsNeevaPage()
                    completion?(false)
                }
            }
        }
    }

    /// Shows the iOS system popup to request notification permission.
    /// Will only show **once**, and if the user has not denied permission already.
    func requestPermissionFromSystem(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [
                .alert, .sound, .badge, .providesAppNotificationSettings,
            ]) { granted, _ in
                print("Notification permission granted: \(granted)")
                DispatchQueue.main.async {
                    ClientLogger.shared.logCounter(
                        granted
                            ? .AuthorizeSystemNotification
                            : .DenySystemNotification
                    )
                }

                completion?(granted)

                guard granted else {
                    Defaults[.notificationPermissionState] =
                        NotificationPermissionStatus.denied.rawValue
                    return
                }

                Defaults[.notificationPermissionState] =
                    NotificationPermissionStatus.authorized.rawValue

                self.registerAuthorizedNotification()
                LocalNotitifications.scheduleNeevaPromoCallback(
                    callSite: LocalNotitifications.ScheduleCallSite.authorizeNotification
                )
            }
    }

    func registerAuthorizedNotification() {
        isAuthorized { authorized in
            guard authorized else { return }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func unregisterRemoteNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func registerDeviceTokenWithServer(deviceToken: String) {
        #if DEBUG
            let environment = "sandbox"
        #else
            let environment = "prod"
        #endif
        AddDeviceTokenIosMutation(
            input: DeviceTokenInput(
                deviceToken: deviceToken,
                deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "",
                environment: environment)
        ).perform { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                log.error("Failed to add device token \(error)")
                break
            }
        }
    }

    func updatePermissionState() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                Defaults[.notificationPermissionState] =
                    NotificationPermissionStatus.authorized.rawValue
            case .denied:
                Defaults[.notificationPermissionState] =
                    NotificationPermissionStatus.denied.rawValue
            default:
                Defaults[.notificationPermissionState] =
                    NotificationPermissionStatus.undecided.rawValue
            }
        }
    }

    init() {
        updatePermissionState()
    }
}
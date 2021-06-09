// Copyright Neeva. All rights reserved.

import Foundation
import Defaults

// Neeva feature flags are server-driven values.
//
// These are fetched as part of the UserInfoQuery, but will remain static for
// the lifetime of the app. This means reported flags may be potentially stale
// until the app gets restarted.
//
// Clients should access feature flags using the `shared` instance of the class.
// That will then initialize from Defaults the set of flag values.
//
// Server feature flags are typed w/ bool, int, float or string values.
//
public class NeevaFeatureFlags {
    private static let boolFlagsKey = Defaults.Key<[Int:Bool]>("neevaBoolFlags", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)
    private static let intFlagsKey = Defaults.Key<[Int:Int]>("neevaIntFlags", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)
    private static let floatFlagsKey = Defaults.Key<[Int:Double]>("neevaFloatFlags", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)
    private static let stringFlagsKey = Defaults.Key<[Int:String]>("neevaStringFlags", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)

    private static let boolFlagOverridesKey = Defaults.Key<[Int:Bool]>("neevaBoolFlagOverrides", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)
    private static let intFlagOverridesKey = Defaults.Key<[Int:Int]>("neevaIntFlagOverrides", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)
    private static let floatFlagOverridesKey = Defaults.Key<[Int:Double]>("neevaFloatFlagOverrides", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)
    private static let stringFlagOverridesKey = Defaults.Key<[Int:String]>("neevaStringFlagOverrides", default: [:], suite: UserDefaults(suiteName: NeevaConstants.appGroup)!)

    public static var shared = NeevaFeatureFlags()

    var boolFlags: [Int: Bool] = [:]
    var intFlags: [Int: Int] = [:]
    var floatFlags: [Int: Double] = [:]
    var stringFlags: [Int: String] = [:]

    // The feature flags we know about. Defined in //neeva/serving/featureflags/flags/.
    // Echo the names as they are defined server-side. Use string names for the flags
    // that mirror the values defined in //neeva/serving/featureflags/data/.

    public enum BoolFlag: Int, CaseIterable {
        case clientHideSearchBox = 34933

        public var name: String {
            switch self {
            case .clientHideSearchBox: return "client.hide_search_box"
            }
        }
    }

    public enum IntFlag: Int, CaseIterable {
        case _unused = 0

        public var name: String {
            return ""
        }
    }

    public enum FloatFlag: Int, CaseIterable {
        case _unused = 0

        public var name: String {
            return ""
        }
    }

    public enum StringFlag: Int, CaseIterable {
        case _unused = 0

        public var name: String {
            return ""
        }
    }

    init() {
        // Initialize from stored data.
        boolFlags = Defaults[Self.boolFlagsKey]
        intFlags = Defaults[Self.intFlagsKey]
        floatFlags = Defaults[Self.floatFlagsKey]
        stringFlags = Defaults[Self.stringFlagsKey]
    }

    public static func update(featureFlags: [UserInfoQuery.Data.User.FeatureFlag]) {
        // Update stored data for next time.

        var boolFlags: [Int: Bool] = [:]
        var intFlags: [Int: Int] = [:]
        var floatFlags: [Int: Double] = [:]
        var stringFlags: [Int: String] = [:]

        for featureFlag in featureFlags {
            // Values have exactly one of value, intValue, floatValue or stringValue
            // set to non-nil. We use that to determine the type of the flag.
            if let boolValue = featureFlag.value {
                boolFlags[featureFlag.id] = boolValue
            } else if let intValue = featureFlag.intValue {
                intFlags[featureFlag.id] = intValue
            } else if let floatValue = featureFlag.floatValue {
                floatFlags[featureFlag.id] = floatValue
            } else if let stringValue = featureFlag.stringValue {
                stringFlags[featureFlag.id] = stringValue
            } else {
                print("Warning: ignoring feature flag \(featureFlag.id) with no value!")
            }
        }

        Defaults[Self.boolFlagsKey] = boolFlags
        Defaults[Self.intFlagsKey] = intFlags
        Defaults[Self.floatFlagsKey] = floatFlags
        Defaults[Self.stringFlagsKey] = stringFlags
    }

    // Get or set feature flags. Setter overrides the server-provided default
    // values. Use reset() methods to restore to server-provided default values.
    // Default values, when we don't have a flag value yet, are consistent with
    // the code in //neeva/serving/featureflags/service.go.

    public static subscript(flag: BoolFlag) -> Bool {
        get {
            return Defaults[Self.boolFlagOverridesKey][flag.rawValue] ?? shared.boolFlags[flag.rawValue] ?? false
        }
        set(newValue) {
            Defaults[Self.boolFlagOverridesKey][flag.rawValue] = newValue
        }
    }

    public static subscript(flag: IntFlag) -> Int {
        get {
            return Defaults[Self.intFlagOverridesKey][flag.rawValue] ?? shared.intFlags[flag.rawValue] ?? 0
        }
        set(newValue) {
            Defaults[Self.intFlagOverridesKey][flag.rawValue] = newValue
        }
    }

    public static subscript(flag: FloatFlag) -> Double {
        get {
            return Defaults[Self.floatFlagOverridesKey][flag.rawValue] ?? shared.floatFlags[flag.rawValue] ?? 0.0
        }
        set(newValue) {
            Defaults[Self.floatFlagOverridesKey][flag.rawValue] = newValue
        }
    }

    public static subscript(flag: StringFlag) -> String {
        get {
            return Defaults[Self.stringFlagOverridesKey][flag.rawValue] ?? shared.stringFlags[flag.rawValue] ?? ""
        }
        set(newValue) {
            Defaults[Self.stringFlagOverridesKey][flag.rawValue] = newValue
        }
    }

    // Reset overrides to the default, server-provided values.

    public static func reset(_ flag: BoolFlag) {
        Defaults[Self.boolFlagOverridesKey][flag.rawValue] = nil
    }

    public static func reset(_ flag: IntFlag) {
        Defaults[Self.intFlagOverridesKey][flag.rawValue] = nil
    }

    public static func reset(_ flag: FloatFlag) {
        Defaults[Self.floatFlagOverridesKey][flag.rawValue] = nil
    }

    public static func reset(_ flag: StringFlag) {
        Defaults[Self.stringFlagOverridesKey][flag.rawValue] = nil
    }

    // Returns true if the flag has been overriden.

    public static func isOverridden(_ flag: BoolFlag) -> Bool {
        return Defaults[Self.boolFlagOverridesKey][flag.rawValue] != nil
    }

    public static func isOverridden(_ flag: IntFlag) -> Bool {
        return Defaults[Self.intFlagOverridesKey][flag.rawValue] != nil
    }

    public static func isOverridden(_ flag: FloatFlag) -> Bool {
        return Defaults[Self.floatFlagOverridesKey][flag.rawValue] != nil
    }

    public static func isOverridden(_ flag: StringFlag) -> Bool {
        return Defaults[Self.stringFlagOverridesKey][flag.rawValue] != nil
    }
}
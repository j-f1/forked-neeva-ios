// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Defaults
import Foundation

public protocol ExperimentArms: Hashable, CaseIterable, RawRepresentable
where RawValue == String, AllCases: RandomAccessCollection {}

public enum NeevaExperiment {
    private static let experimentValuesKey =
        Defaults.Key<[String: String]>("experimentValues", default: [:])

    public static func arm<Arm: ExperimentArms>(for experiment: Experiment<Arm>) -> Arm? {
        guard let armValue = Defaults[self.experimentValuesKey][experiment.key],
            let arm = Arm(rawValue: armValue)
        else {
            return nil
        }

        return arm
    }

    public static func startExperiment<Arm: ExperimentArms>(for experiment: Experiment<Arm>) -> Arm
    {
        if let rawValue = Defaults[self.experimentValuesKey][experiment.key],
            let arm = Arm(rawValue: rawValue)
        {
            return arm
        }

        guard let arm = Arm.allCases.randomElement() else {
            fatalError("Empty experiment \(Arm.self)")
        }
        Defaults[self.experimentValuesKey][experiment.key] = arm.rawValue

        return arm
    }

    public struct Experiment<Arm: ExperimentArms> {
        public let key: String

        init(key: String = "\(Arm.self)") {
            self.key = key
        }
    }

    //MARK: Debug Helpers
    static public func resetAllExperiments() {
        Defaults[self.experimentValuesKey] = [:]
    }

    static public func resetExperiment<Arm: ExperimentArms>(
        experiment: Experiment<Arm>
    ) {
        Defaults[self.experimentValuesKey][experiment.key] = nil
    }

    static public func forceExperimentArm<Arm: ExperimentArms>(
        experiment: Experiment<Arm>,
        experimentArm: String?
    ) {
        Defaults[self.experimentValuesKey][experiment.key] = experimentArm
    }
}

extension NeevaExperiment {
    public enum DefaultBrowserV2: String, ExperimentArms {
        case control
        case showDBPrompt
    }
}

extension NeevaExperiment.Experiment where Arm == NeevaExperiment.DefaultBrowserV2 {
    public static let defaultBrowserPromptV2 = Self()
}

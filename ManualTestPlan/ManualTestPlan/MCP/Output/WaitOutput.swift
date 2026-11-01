//
//  WaitOutput.swift
//  ManualTestPlan
//

import Foundation

/// Reply to `wait_for_test_plan`.
nonisolated struct WaitOutput: Encodable {
    /// Whether the user recorded a verdict or attached evidence since `since_revision`.
    var changed: Bool
    /// True when the wait ended only because the timeout elapsed.
    var timedOut: Bool
    /// What the agent should do next.
    var hint: String
    /// The plan's current state (failed and blocked steps only; call `get_test_plan` for every step).
    var plan: PlanOutput
}

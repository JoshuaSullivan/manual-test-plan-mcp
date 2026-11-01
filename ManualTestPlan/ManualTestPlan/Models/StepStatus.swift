//
//  StepStatus.swift
//  ManualTestPlan
//

import Foundation

/// The user's verdict on a single test step. Also used for the rolled-up status of a case or plan.
nonisolated enum StepStatus: String, Codable, Sendable, CaseIterable {
    /// The user hasn't judged this step yet.
    case pending
    /// The step behaved as expected.
    case passed
    /// The step did not behave as expected.
    case failed
    /// The step couldn't be verified, typically because the instructions didn't match what the UI actually shows.
    case blocked

    /// Computes the status that summarizes a group of steps.
    ///
    /// Precedence: any `failed` wins, then any `blocked`, then any `pending`; otherwise `passed`.
    /// An empty group is `pending` because there is nothing to have passed.
    /// - Parameter statuses: The statuses of the steps (or child groups) being summarized.
    init(rollingUp statuses: some Sequence<StepStatus>) {
        var sawAny = false
        var sawBlocked = false
        var sawPending = false
        for status in statuses {
            sawAny = true
            switch status {
            case .failed:
                self = .failed
                return
            case .blocked: sawBlocked = true
            case .pending: sawPending = true
            case .passed: break
            }
        }
        if !sawAny || sawPending && !sawBlocked {
            self = .pending
        } else if sawBlocked {
            self = .blocked
        } else {
            self = .passed
        }
    }
}

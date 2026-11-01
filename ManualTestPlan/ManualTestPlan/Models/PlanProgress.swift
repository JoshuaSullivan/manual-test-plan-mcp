//
//  PlanProgress.swift
//  ManualTestPlan
//

import Foundation

/// Step counts by status, for progress bars and agent-facing summaries.
nonisolated struct PlanProgress: Codable, Sendable, Hashable {
    /// Steps awaiting a verdict.
    var pending = 0
    /// Steps the user marked passed.
    var passed = 0
    /// Steps the user marked failed.
    var failed = 0
    /// Steps the user marked blocked.
    var blocked = 0

    /// Total number of steps.
    var total: Int { pending + passed + failed + blocked }

    /// Steps that have a verdict of any kind.
    var resolved: Int { total - pending }

    /// Records one step's status.
    /// - Parameter status: The status to count.
    mutating func add(_ status: StepStatus) {
        switch status {
        case .pending: pending += 1
        case .passed: passed += 1
        case .failed: failed += 1
        case .blocked: blocked += 1
        }
    }
}

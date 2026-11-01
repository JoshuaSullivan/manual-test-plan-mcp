//
//  PlanStoreError.swift
//  ManualTestPlan
//

import Foundation

/// Errors returned by ``PlanStore``. The descriptions are shown to agents, so they say what to do next.
nonisolated enum PlanStoreError: LocalizedError, Equatable {
    /// No active plan has this ID. It may have been completed, or the ID may be mistyped.
    case planNotFound(String)
    /// The plan has no test case with this ID.
    case caseNotFound(String)
    /// The plan has no step with this ID.
    case stepNotFound(String)
    /// The plan can't be completed because these steps still have no verdict.
    case unresolvedSteps([String])
    /// The plan is in the middle of being completed and deleted.
    case planIsBeingCompleted(String)
    /// An attachment exceeds the size limit.
    case evidenceTooLarge(name: String, limit: Int)

    var errorDescription: String? {
        switch self {
        case .planNotFound(let id):
            "No active test plan with ID '\(id)'. It may already have been completed, or the ID may be wrong. Use list_test_plans to see active plans."
        case .caseNotFound(let id):
            "No test case with ID '\(id)' in this plan."
        case .stepNotFound(let id):
            "No step with ID '\(id)' in this plan."
        case .unresolvedSteps(let ids):
            "\(ids.count) step(s) still have no verdict: \(ids.joined(separator: ", ")). Wait for the user to finish, or pass force=true to discard the plan anyway."
        case .planIsBeingCompleted(let id):
            "Test plan '\(id)' is being completed."
        case .evidenceTooLarge(let name, let limit):
            "'\(name)' is larger than the \(limit.formatted(.byteCount(style: .file))) attachment limit."
        }
    }
}

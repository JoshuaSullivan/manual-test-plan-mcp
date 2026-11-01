//
//  PlanOutput.swift
//  ManualTestPlan
//

import Foundation

/// A plan with its results, as reported to agents.
nonisolated struct PlanOutput: Encodable {
    var planId: String
    var title: String
    var summary: String?
    var context: String?
    var agent: String?
    var status: StepStatus
    /// True once every step has a verdict.
    var resolved: Bool
    /// Pass this back as `since_revision` to `wait_for_test_plan`.
    var revision: Int
    var progress: PlanProgress
    var createdAt: Date
    var updatedAt: Date
    var cases: [CaseOutput]

    /// - Parameters:
    ///   - plan: The plan to describe.
    ///   - revision: ``PlanStore/userRevision(of:)`` at the time of the call.
    ///   - detail: Whether to list every step or only failed and blocked ones.
    init(_ plan: TestPlan, revision: Int, detail: CaseOutput.Detail) {
        planId = plan.id
        title = plan.title
        summary = plan.summary.isEmpty ? nil : plan.summary
        context = plan.context.isEmpty ? nil : plan.context
        agent = plan.agentName
        status = plan.status
        resolved = plan.isResolved
        self.revision = revision
        progress = plan.progress
        createdAt = plan.createdAt
        updatedAt = plan.updatedAt
        cases = plan.cases.map { CaseOutput($0, detail: detail) }
    }
}

//
//  PlanListItem.swift
//  ManualTestPlan
//

import Foundation

/// One row of `list_test_plans`.
nonisolated struct PlanListItem: Encodable {
    var planId: String
    var title: String
    var agent: String?
    var status: StepStatus
    var resolved: Bool
    var progress: PlanProgress
    var createdAt: Date
    var updatedAt: Date

    init(_ plan: TestPlan) {
        planId = plan.id
        title = plan.title
        agent = plan.agentName
        status = plan.status
        resolved = plan.isResolved
        progress = plan.progress
        createdAt = plan.createdAt
        updatedAt = plan.updatedAt
    }
}

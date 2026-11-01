//
//  CaseOutput.swift
//  ManualTestPlan
//

import Foundation

/// A test case as reported to agents.
nonisolated struct CaseOutput: Encodable {
    /// How much step detail to include.
    enum Detail: Sendable {
        /// Only steps the user failed or blocked, which are the ones needing the agent's attention.
        case summary
        /// Every step.
        case full
    }

    var caseId: String
    var title: String
    var preconditions: String?
    var status: StepStatus
    var progress: PlanProgress
    var steps: [StepOutput]

    init(_ testCase: TestCase, detail: Detail) {
        caseId = testCase.id
        title = testCase.title
        preconditions = testCase.preconditions.isEmpty ? nil : testCase.preconditions
        status = testCase.status
        var progress = PlanProgress()
        testCase.steps.forEach { progress.add($0.status) }
        self.progress = progress
        steps = testCase.steps
            .filter { detail == .full || $0.status == .failed || $0.status == .blocked }
            .map { StepOutput($0) }
    }
}

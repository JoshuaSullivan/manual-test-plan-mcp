//
//  StepStatusTests.swift
//  ManualTestPlanTests
//

import Testing
@testable import ManualTestPlan

struct StepStatusTests {
    @Test(arguments: [
        ([StepStatus](), StepStatus.pending),
        ([.passed], .passed),
        ([.passed, .passed], .passed),
        ([.passed, .pending], .pending),
        ([.pending, .pending], .pending),
        ([.passed, .blocked], .blocked),
        ([.pending, .blocked], .blocked),
        ([.blocked, .failed], .failed),
        ([.passed, .pending, .blocked, .failed], .failed)
    ])
    func rollup(statuses: [StepStatus], expected: StepStatus) {
        #expect(StepStatus(rollingUp: statuses) == expected)
    }
}

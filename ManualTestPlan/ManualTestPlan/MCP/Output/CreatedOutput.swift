//
//  CreatedOutput.swift
//  ManualTestPlan
//

import Foundation

/// Reply to `create_test_plan` and `add_to_test_plan`: the IDs the agent needs to address new items later.
nonisolated struct CreatedOutput: Encodable {
    /// A created case and its steps.
    struct Case: Encodable {
        var caseId: String
        var title: String
        var steps: [Step]

        init(_ testCase: TestCase) {
            caseId = testCase.id
            title = testCase.title
            steps = testCase.steps.map(Step.init)
        }
    }

    /// A created step.
    struct Step: Encodable {
        var stepId: String
        var instruction: String

        init(_ step: TestStep) {
            stepId = step.id
            instruction = step.instruction
        }
    }

    var planId: String
    var message: String
    /// New cases, each with its steps.
    var cases: [Case]
    /// Steps appended to an existing case (empty when whole cases were added).
    var steps: [Step]

    init(planID: String, message: String, cases: [TestCase] = [], steps: [TestStep] = []) {
        planId = planID
        self.message = message
        self.cases = cases.map(Case.init)
        self.steps = steps.map(Step.init)
    }
}

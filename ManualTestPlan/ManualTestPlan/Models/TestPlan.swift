//
//  TestPlan.swift
//  ManualTestPlan
//

import Foundation

/// A manual test plan created by an agent for the user to work through.
///
/// Plans are plain value types. `PlanStore` owns the live copies and `PlanPersistence` writes them to disk.
nonisolated struct TestPlan: Codable, Sendable, Hashable, Identifiable {
    /// Opaque ID the agent uses to query the plan, such as `tp_7f3k2a`.
    var id: String
    /// Short title shown in the window and menu.
    var title: String
    /// What is being tested and why.
    var summary: String
    /// Optional free text from the agent, such as the project, build, or branch under test.
    var context: String
    /// The MCP client that created the plan (from `clientInfo.name`), if it identified itself.
    var agentName: String?
    /// When the plan was created.
    var createdAt: Date
    /// When anything in the plan last changed.
    var updatedAt: Date
    /// The test cases, in display order.
    var cases: [TestCase]

    /// Creates a plan with a fresh ID.
    /// - Parameters:
    ///   - title: Short title.
    ///   - summary: What is being tested and why.
    ///   - context: Optional project/build details.
    ///   - agentName: The creating MCP client's name.
    ///   - cases: The test cases.
    init(
        title: String,
        summary: String = "",
        context: String = "",
        agentName: String? = nil,
        cases: [TestCase] = []
    ) {
        self.id = ShortID.make(prefix: "tp")
        self.title = title
        self.summary = summary
        self.context = context
        self.agentName = agentName
        self.createdAt = .now
        self.updatedAt = .now
        self.cases = cases
    }

    /// The summarized status of every step in the plan.
    var status: StepStatus {
        StepStatus(rollingUp: cases.map(\.status))
    }

    /// Step counts by status across all cases.
    var progress: PlanProgress {
        var progress = PlanProgress()
        for step in cases.lazy.flatMap(\.steps) {
            progress.add(step.status)
        }
        return progress
    }

    /// Whether every step has a verdict. An empty plan counts as unresolved.
    var isResolved: Bool {
        let progress = progress
        return progress.total > 0 && progress.pending == 0
    }

    /// Every step ID in the plan, for uniqueness checks.
    var allStepIDs: Set<String> {
        Set(cases.flatMap(\.steps).map(\.id))
    }

    /// Finds a step by ID.
    /// - Parameter stepID: The step's ID.
    /// - Returns: The case and step indices, or `nil` if no step has that ID.
    func location(ofStep stepID: String) -> (caseIndex: Int, stepIndex: Int)? {
        for (caseIndex, testCase) in cases.enumerated() {
            if let stepIndex = testCase.steps.firstIndex(where: { $0.id == stepID }) {
                return (caseIndex, stepIndex)
            }
        }
        return nil
    }

    /// The step with the given ID, if any.
    /// - Parameter stepID: The step's ID.
    func step(withID stepID: String) -> TestStep? {
        guard let location = location(ofStep: stepID) else { return nil }
        return cases[location.caseIndex].steps[location.stepIndex]
    }
}

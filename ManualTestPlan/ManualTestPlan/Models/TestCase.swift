//
//  TestCase.swift
//  ManualTestPlan
//

import Foundation

/// A named group of steps that verify one behavior. Shown as a collapsible section.
nonisolated struct TestCase: Codable, Sendable, Hashable, Identifiable {
    /// Unique ID within the plan; agents use it to address the case.
    var id: String
    /// Short title, such as "Dragging a card between columns".
    var title: String
    /// Setup the user needs before starting the steps. Empty when none is needed.
    var preconditions: String
    /// The steps, in the order the user should perform them.
    var steps: [TestStep]

    /// Creates a case with a fresh ID.
    /// - Parameters:
    ///   - title: Short title.
    ///   - preconditions: Setup required before the first step.
    ///   - steps: The steps to perform.
    init(title: String, preconditions: String = "", steps: [TestStep] = []) {
        self.id = ShortID.make(prefix: "tc")
        self.title = title
        self.preconditions = preconditions
        self.steps = steps
    }

    /// The summarized status of all steps in this case.
    var status: StepStatus {
        StepStatus(rollingUp: steps.map(\.status))
    }
}

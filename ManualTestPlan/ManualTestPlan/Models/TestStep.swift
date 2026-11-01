//
//  TestStep.swift
//  ManualTestPlan
//

import Foundation

/// One action for the user to perform and judge.
nonisolated struct TestStep: Codable, Sendable, Hashable, Identifiable {
    /// Unique ID within the plan; agents use it to address the step.
    var id: String
    /// What the user should do, written by the agent.
    var instruction: String
    /// What the user should see if the step works. Empty when the instruction is self-explanatory.
    var expected: String
    /// The user's verdict.
    var status: StepStatus
    /// Free-form text the user typed while judging the step.
    var note: String
    /// Images the user attached as evidence.
    var evidence: [EvidenceImage]
    /// When the step was last changed by the user or the agent.
    var updatedAt: Date

    /// Creates a pending step with a fresh ID.
    /// - Parameters:
    ///   - instruction: What the user should do.
    ///   - expected: What the user should observe.
    init(instruction: String, expected: String = "") {
        self.id = ShortID.make(prefix: "st")
        self.instruction = instruction
        self.expected = expected
        self.status = .pending
        self.note = ""
        self.evidence = []
        self.updatedAt = .now
    }
}

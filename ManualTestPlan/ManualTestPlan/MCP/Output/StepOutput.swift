//
//  StepOutput.swift
//  ManualTestPlan
//

import Foundation

/// A step as reported to agents. Encoded with `snake_case` keys; empty strings are omitted.
nonisolated struct StepOutput: Encodable {
    var stepId: String
    var instruction: String
    var expected: String?
    var status: StepStatus
    var note: String?
    var evidenceCount: Int
    var updatedAt: Date

    init(_ step: TestStep) {
        stepId = step.id
        instruction = step.instruction
        expected = step.expected.isEmpty ? nil : step.expected
        status = step.status
        note = step.note.isEmpty ? nil : step.note
        evidenceCount = step.evidence.count
        updatedAt = step.updatedAt
    }
}

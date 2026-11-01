//
//  StepOutput.swift
//  ManualTestPlan
//

import Foundation

/// An attachment as listed to agents.
nonisolated struct EvidenceOutput: Encodable {
    var evidenceId: String
    var name: String
    var mimeType: String
    var bytes: Int
    /// Where the file lives on disk. Only included by `get_step_evidence`.
    var localPath: String?

    init(_ file: EvidenceFile, localPath: String? = nil) {
        evidenceId = file.id
        name = file.name
        mimeType = file.mimeType
        bytes = file.byteCount
        self.localPath = localPath
    }
}

/// A step as reported to agents. Encoded with `snake_case` keys; empty strings are omitted.
nonisolated struct StepOutput: Encodable {
    var stepId: String
    var instruction: String
    var expected: String?
    var status: StepStatus
    var note: String?
    var evidenceCount: Int
    /// The attachments, omitted when there are none.
    var evidence: [EvidenceOutput]?
    var updatedAt: Date

    /// - Parameters:
    ///   - step: The step to describe.
    ///   - localPath: Maps an attachment to its on-disk path; nil omits paths.
    init(_ step: TestStep, localPath: (EvidenceFile) -> String? = { _ in nil }) {
        stepId = step.id
        instruction = step.instruction
        expected = step.expected.isEmpty ? nil : step.expected
        status = step.status
        note = step.note.isEmpty ? nil : step.note
        evidenceCount = step.evidence.count
        evidence = step.evidence.isEmpty ? nil : step.evidence.map { EvidenceOutput($0, localPath: localPath($0)) }
        updatedAt = step.updatedAt
    }
}

//
//  EvidenceAttacher.swift
//  ManualTestPlan
//

import Foundation

/// Attaches dropped, pasted, or picked items to one step and reports what went wrong, if anything.
@MainActor
struct EvidenceAttacher {
    let store: PlanStore
    let planID: String
    let stepID: String

    /// Prepares and attaches each payload. One failure doesn't stop the others.
    /// - Parameter payloads: Items from a drop or paste.
    /// - Returns: User-facing messages for every item that could not be attached; empty on full success.
    func attach(_ payloads: [AttachmentPayload]) async -> [String] {
        var failures: [String] = []
        for payload in payloads {
            if let problem = payload.problem {
                failures.append(problem)
                continue
            }
            let prepared = await AttachmentPreparer.prepare(payload)
            do {
                try await store.addEvidence(prepared.data, named: prepared.name, toStep: stepID, inPlan: planID)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return failures
    }

    /// Reads and attaches files chosen in an open panel.
    /// - Parameter urls: The chosen files.
    /// - Returns: User-facing failure messages, as for ``attach(_:)``.
    func attach(urls: [URL]) async -> [String] {
        await attach(urls.map(AttachmentPayload.load(from:)))
    }
}

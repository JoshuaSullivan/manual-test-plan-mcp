//
//  EvidenceImage.swift
//  ManualTestPlan
//

import Foundation

/// A reference to an image the user attached to a step as evidence for their verdict.
///
/// The image bytes live on disk inside the owning plan's directory, never in `plan.json`.
nonisolated struct EvidenceImage: Codable, Sendable, Hashable, Identifiable {
    /// Unique ID; also the base name of the PNG file on disk.
    var id: String
    /// When the user attached the image.
    var addedAt: Date

    /// Creates a reference with a fresh ID.
    /// - Parameter addedAt: When the image was attached.
    init(addedAt: Date = .now) {
        self.id = ShortID.make(prefix: "ev", length: 8)
        self.addedAt = addedAt
    }

    /// The file name of the image inside the plan's `evidence` directory.
    var filename: String { "\(id).png" }
}

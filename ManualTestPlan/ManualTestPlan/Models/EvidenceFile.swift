//
//  EvidenceFile.swift
//  ManualTestPlan
//

import Foundation
import UniformTypeIdentifiers

/// A file the user attached to a step as evidence for their verdict: a screenshot, a log, a crash report,
/// a recording, or anything else.
///
/// Only this metadata lives in `plan.json`. The bytes are stored inside the owning plan's directory under
/// ``storedFilename``, which is derived from a random ID rather than the user's file name so arbitrary names
/// can never collide or escape the directory.
nonisolated struct EvidenceFile: Codable, Sendable, Hashable, Identifiable {
    /// The largest file that can be attached. Larger files are refused rather than copied.
    static let maxByteCount = 25 * 1024 * 1024

    /// Unique ID; also the base name of the file on disk.
    var id: String
    /// The name to show the user and the agent, such as `crash.log`.
    var name: String
    /// Sanitized lowercase extension used for the stored file, or `bin` when the original had none.
    var fileExtension: String
    /// Best-effort MIME type from the extension, or `application/octet-stream`.
    var mimeType: String
    /// Size of the file in bytes.
    var byteCount: Int
    /// When the user attached the file.
    var addedAt: Date

    /// Creates a record with a fresh ID.
    /// - Parameters:
    ///   - name: The original file name. Blank names become "Attachment".
    ///   - byteCount: The file's size.
    ///   - addedAt: When it was attached.
    init(name: String, byteCount: Int, addedAt: Date = .now) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? "Attachment" : trimmed
        let rawExtension = URL(filePath: displayName).pathExtension.lowercased()
        let cleaned = String(rawExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(16))

        self.id = ShortID.make(prefix: "ev", length: 8)
        self.name = displayName
        self.fileExtension = cleaned.isEmpty ? "bin" : cleaned
        self.mimeType = UTType(filenameExtension: cleaned)?.preferredMIMEType ?? "application/octet-stream"
        self.byteCount = byteCount
        self.addedAt = addedAt
    }

    /// The file name inside the plan's `evidence` directory.
    var storedFilename: String { "\(id).\(fileExtension)" }

    /// Whether the file is an image the UI can thumbnail and the agent can view directly.
    var isImage: Bool { mimeType.hasPrefix("image/") }
}

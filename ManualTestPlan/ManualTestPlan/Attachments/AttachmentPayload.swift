//
//  AttachmentPayload.swift
//  ManualTestPlan
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A file (or image data) the user dropped, pasted, or picked, before it is attached to a step.
///
/// Conforming to `Transferable` lets SwiftUI's drop and paste destinations produce these directly. File
/// representations are preferred, so Finder drops keep their real name and bytes; raw image data (a
/// screenshot on the pasteboard, an image dragged from a web page) arrives with an empty name.
nonisolated struct AttachmentPayload: Transferable, Sendable, Equatable {
    /// The file name, or empty for anonymous image data.
    var name: String
    /// The contents. Empty when ``problem`` is set.
    var data: Data
    /// Why the item could not be read, to show the user. Imports never throw, because SwiftUI discards
    /// failed imports silently and the user would see nothing happen.
    var problem: String?

    /// Creates a payload with contents.
    init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    /// Creates a payload that records a failure.
    init(name: String, problem: String) {
        self.name = name
        self.data = Data()
        self.problem = problem
    }

    /// Reads a file from disk, enforcing the attachment size limit before loading it into memory.
    ///
    /// Works for URLs from drops and file pickers, which carry implicit sandbox access, by opening a
    /// security scope when the URL needs one.
    /// - Parameter url: The file to read.
    static func load(from url: URL) -> AttachmentPayload {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values.isDirectory == true {
                return AttachmentPayload(name: name, problem: "'\(name)' is a folder. Attach a file, or compress the folder first.")
            }
            let size = values.fileSize ?? 0
            guard size <= EvidenceFile.maxByteCount else {
                return AttachmentPayload(name: name, problem: PlanStoreError.evidenceTooLarge(name: name, limit: EvidenceFile.maxByteCount).localizedDescription)
            }
            return AttachmentPayload(name: name, data: try Data(contentsOf: url))
        } catch {
            return AttachmentPayload(name: name, problem: "'\(name)' couldn't be read: \(error.localizedDescription)")
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            AttachmentPayload.load(from: received.file)
        }
        DataRepresentation(importedContentType: .image) { data in
            AttachmentPayload(name: "", data: data)
        }
    }
}

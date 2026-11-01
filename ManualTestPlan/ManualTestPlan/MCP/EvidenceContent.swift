//
//  EvidenceContent.swift
//  ManualTestPlan
//

import Foundation

/// Converts an attached file into MCP content blocks an agent can actually use.
nonisolated enum EvidenceContent {
    /// The most text returned inline. Longer text keeps its beginning and end, which for logs is where the
    /// start-up context and the final error usually are; the full file is available at its local path.
    static let maxInlineTextBytes = 64 * 1024

    /// How much of the file is sniffed when deciding whether it is text.
    private static let sniffByteCount = 8 * 1024

    /// Builds the content blocks for one attachment.
    ///
    /// - Images become `image` blocks, so a vision-capable model sees them.
    /// - Files that look like text (by content, not extension) become `text` blocks, truncated in the middle
    ///   if they exceed ``maxInlineTextBytes``.
    /// - Anything else becomes a short description so the agent knows it exists.
    ///
    /// Every non-image block names the file and, when known, where it lives on disk.
    /// - Parameters:
    ///   - file: The attachment's metadata.
    ///   - data: The attachment's bytes.
    ///   - localPath: The file's path on disk, for files too large or too binary to inline.
    static func blocks(for file: EvidenceFile, data: Data, localPath: String?) -> [MCPContent] {
        if file.isImage {
            return [.image(data, mimeType: file.mimeType)]
        }

        let size = data.count.formatted(.byteCount(style: .file))
        let location = localPath.map { "\nLocal path (deleted when the plan is completed): \($0)" } ?? ""

        guard looksLikeText(data) else {
            return [.text("Attachment '\(file.name)' (\(file.mimeType), \(size)) is binary and was not included inline.\(location)")]
        }

        if data.count <= maxInlineTextBytes {
            return [.text("Attachment '\(file.name)' (\(size)):\n\(String(decoding: data, as: UTF8.self))")]
        }

        let half = maxInlineTextBytes / 2
        let head = String(decoding: data.prefix(half), as: UTF8.self)
        let tail = String(decoding: data.suffix(half), as: UTF8.self)
        let omitted = (data.count - maxInlineTextBytes).formatted(.byteCount(style: .file))
        return [.text("""
            Attachment '\(file.name)' (\(size)); the middle \(omitted) is omitted.\(location)
            --- beginning ---
            \(head)
            --- \(omitted) omitted ---
            \(tail)
            --- end ---
            """)]
    }

    /// Whether the data is plausibly UTF-8 text: no NUL bytes and valid encoding in the sampled prefix.
    static func looksLikeText(_ data: Data) -> Bool {
        let sample = data.prefix(sniffByteCount)
        if sample.isEmpty { return true }
        guard !sample.contains(0) else { return false }
        // A multi-byte character may be cut off at the end of the sample; tolerate up to 3 stray bytes.
        for trim in 0...3 where sample.count > trim {
            if String(validating: sample.dropLast(trim), as: UTF8.self) != nil { return true }
        }
        return false
    }
}

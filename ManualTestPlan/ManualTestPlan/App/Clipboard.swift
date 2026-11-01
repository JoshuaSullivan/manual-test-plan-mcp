//
//  Clipboard.swift
//  ManualTestPlan
//

import AppKit

/// Thin wrapper over the general pasteboard so views don't touch AppKit directly.
enum Clipboard {
    /// Replaces the pasteboard contents with plain text.
    /// - Parameter text: The text to copy.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

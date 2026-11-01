//
//  ShortID.swift
//  ManualTestPlan
//

import Foundation

/// Generates short, opaque, human- and agent-friendly identifiers such as `tp_7f3k2a`.
///
/// IDs are random rather than sequential so that an agent can't guess another agent's plan ID, and
/// they avoid visually ambiguous characters (`0/o`, `1/l/i`) because users and agents copy them around.
nonisolated enum ShortID {
    /// Lowercase alphanumerics without `0`, `1`, `i`, `l`, or `o`.
    private static let alphabet = Array("23456789abcdefghjkmnpqrstuvwxyz")

    /// Creates a new random identifier.
    /// - Parameters:
    ///   - prefix: A short type tag joined to the random part with an underscore, such as `tp`.
    ///   - length: The number of random characters.
    /// - Returns: An identifier like `tp_7f3k2a`.
    static func make(prefix: String, length: Int = 6) -> String {
        let random = String((0..<length).compactMap { _ in alphabet.randomElement() })
        return "\(prefix)_\(random)"
    }
}

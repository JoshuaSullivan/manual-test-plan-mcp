//
//  StepStatus+Display.swift
//  ManualTestPlan
//

import SwiftUI

extension StepStatus {
    /// The status shown to the user.
    var title: LocalizedStringKey {
        switch self {
        case .pending: "Pending"
        case .passed: "Passed"
        case .failed: "Failed"
        case .blocked: "Blocked"
        }
    }

    /// SF Symbol for this status.
    var symbolName: String {
        switch self {
        case .pending: "circle"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .blocked: "exclamationmark.triangle.fill"
        }
    }

    /// Accent color for this status.
    var tint: Color {
        switch self {
        case .pending: .secondary
        case .passed: .green
        case .failed: .red
        case .blocked: .orange
        }
    }

    /// The status a step should have after the user taps this status's button.
    ///
    /// Tapping the status a step already has clears it back to pending, so a misclick is easy to undo.
    /// - Parameter current: The step's present status.
    nonisolated func afterSelecting(from current: StepStatus) -> StepStatus {
        current == self ? .pending : self
    }
}

//
//  PlanReport.swift
//  ManualTestPlan
//

import Foundation

/// Renders a plan's results as Markdown, for the agent's final report and the user's "Copy report" button.
nonisolated enum PlanReport {
    /// Renders the plan.
    /// - Parameters:
    ///   - plan: The plan to describe.
    ///   - includeIDs: Whether to print case and step IDs, which an agent needs but a human reader doesn't.
    static func markdown(for plan: TestPlan, includeIDs: Bool = false) -> String {
        var lines = ["# \(plan.title)", ""]
        if !plan.summary.isEmpty {
            lines += [plan.summary, ""]
        }
        if !plan.context.isEmpty {
            lines += ["**Context:** \(plan.context)", ""]
        }
        let progress = plan.progress
        lines += [
            "**Result: \(label(plan.status))** — \(progress.passed) passed, \(progress.failed) failed, "
                + "\(progress.blocked) blocked, \(progress.pending) pending (\(progress.total) steps)",
            ""
        ]

        for testCase in plan.cases {
            lines.append("## \(testCase.title) — \(label(testCase.status))" + idSuffix(testCase.id, includeIDs))
            if !testCase.preconditions.isEmpty {
                lines.append("*Preconditions:* \(testCase.preconditions)")
            }
            lines.append("")
            for (index, step) in testCase.steps.enumerated() {
                lines.append("\(index + 1). **\(label(step.status))** \(step.instruction)" + idSuffix(step.id, includeIDs))
                if !step.expected.isEmpty {
                    lines.append("   - Expected: \(step.expected)")
                }
                if !step.note.isEmpty {
                    let note = step.note.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n     ")
                    lines.append("   - Note: \(note)")
                }
                if !step.evidence.isEmpty {
                    lines.append("   - Evidence: \(step.evidence.map(\.name).joined(separator: ", "))")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func label(_ status: StepStatus) -> String {
        switch status {
        case .pending: "PENDING"
        case .passed: "PASS"
        case .failed: "FAIL"
        case .blocked: "BLOCKED"
        }
    }

    private static func idSuffix(_ id: String, _ include: Bool) -> String {
        include ? " (`\(id)`)" : ""
    }
}

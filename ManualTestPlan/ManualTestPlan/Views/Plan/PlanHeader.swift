//
//  PlanHeader.swift
//  ManualTestPlan
//

import SwiftUI

/// Title, description, who created the plan, and overall progress.
struct PlanHeader: View {
    let plan: TestPlan

    var body: some View {
        let progress = plan.progress
        VStack(alignment: .leading) {
            Text(plan.title)
                .font(.title)
                .bold()

            if !plan.summary.isEmpty {
                Text(plan.summary)
            }
            if !plan.context.isEmpty {
                Text(plan.context)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let agent = plan.agentName {
                Label("Created by \(agent)", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(progress.resolved), total: Double(max(progress.total, 1)))

            HStack {
                CountBadge(status: .passed, count: progress.passed)
                CountBadge(status: .failed, count: progress.failed)
                CountBadge(status: .blocked, count: progress.blocked)
                CountBadge(status: .pending, count: progress.pending)
            }
            .font(.callout)
        }
    }
}

/// An icon and a count for one status.
private struct CountBadge: View {
    let status: StepStatus
    let count: Int

    var body: some View {
        Label {
            Text(count, format: .number)
                .monospacedDigit()
        } icon: {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
        }
        .accessibilityLabel(Text("\(count) \(status.rawValue)"))
    }
}

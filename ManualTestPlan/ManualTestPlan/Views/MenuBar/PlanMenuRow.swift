//
//  PlanMenuRow.swift
//  ManualTestPlan
//

import SwiftUI

/// One plan in the menu bar popover: status, title, and progress. Tapping opens the plan's window.
struct PlanMenuRow: View {
    let plan: TestPlan
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(plan.title)
                            .lineLimit(1)
                        if let agent = plan.agentName {
                            Text(agent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: plan.status.symbolName)
                        .foregroundStyle(plan.status.tint)
                }
                Spacer()
                Text("\(plan.progress.resolved) of \(plan.progress.total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

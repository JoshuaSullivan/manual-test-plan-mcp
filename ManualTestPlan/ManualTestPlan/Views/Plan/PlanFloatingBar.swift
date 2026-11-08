//
//  PlanFloatingBar.swift
//  ManualTestPlan
//

import SwiftUI

/// A compact progress bar with previous/next buttons, shown over the top of a plan window once the header
/// has scrolled out of view. The buttons jump to the nearest step that still has no verdict.
struct PlanFloatingBar: View {
    let progress: PlanProgress
    let goToPrevious: () -> Void
    let goToNext: () -> Void

    var body: some View {
        HStack {
            ProgressView(value: Double(progress.resolved), total: Double(max(progress.total, 1)))

            Text("\(progress.resolved) of \(progress.total)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button("Previous Unaddressed Step", systemImage: "chevron.up", action: goToPrevious)
                .help("Jump to the previous step without a verdict")
            Button("Next Unaddressed Step", systemImage: "chevron.down", action: goToNext)
                .help("Jump to the next step without a verdict")
        }
        .labelStyle(.iconOnly)
        .disabled(progress.pending == 0)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .shadow(radius: 6)
        .accessibilityElement(children: .contain)
    }
}

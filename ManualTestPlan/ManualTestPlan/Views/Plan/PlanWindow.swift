//
//  PlanWindow.swift
//  ManualTestPlan
//

import SwiftUI

/// The window for one test plan. Closes itself when the agent completes the plan.
struct PlanWindow: View {
    let planID: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = model.store.plan(id: planID)
        Group {
            if let plan {
                PlanContent(plan: plan)
            } else {
                ContentUnavailableView(
                    "Plan Finished",
                    systemImage: "checkmark.circle",
                    description: Text("This plan was completed by the agent or no longer exists.")
                )
            }
        }
        .navigationTitle(plan?.title ?? "Test Plan")
        // Wait for the initial disk load so a restored window isn't dismissed before its plan appears.
        .onChange(of: model.store.isLoaded && plan == nil, initial: true) { _, isGone in
            if isGone { dismiss() }
        }
    }
}

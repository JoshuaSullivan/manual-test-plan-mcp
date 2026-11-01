//
//  MenuBarLabel.swift
//  ManualTestPlan
//

import AppKit
import SwiftUI

/// The status item itself. It is also the app's always-alive view, so it does the work that has to happen
/// without any window open: starting the model and opening plan windows when an agent creates a plan.
struct MenuBarLabel: View {
    /// Receives the model so it can flush saves on quit.
    let delegate: AppDelegate

    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let waiting = model.plansNeedingAttention.count
        HStack {
            Image(systemName: waiting > 0 ? "checklist.unchecked" : "checklist")
            if waiting > 0 {
                Text(waiting, format: .number)
            }
        }
        .task {
            delegate.model = model
            await model.start()
        }
        .onChange(of: model.store.windowRequests, initial: true) { _, requests in
            guard !requests.isEmpty else { return }
            for planID in requests {
                openWindow(value: planID)
                model.store.consumeWindowRequest(planID)
            }
            NSApplication.shared.activate()
        }
    }
}

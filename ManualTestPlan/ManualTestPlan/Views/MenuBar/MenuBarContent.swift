//
//  MenuBarContent.swift
//  ManualTestPlan
//

import AppKit
import SwiftUI

/// The popover shown when the user clicks the status item.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading) {
            Text("Manual Test Plans")
                .font(.headline)

            ServerStatusRow(state: model.server.state)

            Divider()

            if model.store.plans.isEmpty {
                Text("No active plans. Ask your agent to create one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.store.plans) { plan in
                    PlanMenuRow(plan: plan) {
                        model.store.requestWindow(for: plan.id)
                    }
                }
            }

            Divider()

            Button("Copy MCP Setup Command", systemImage: "terminal") {
                Clipboard.copy(model.setupCommand)
            }
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            Button("Quit ManualTestPlan", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding()
        .frame(minWidth: 320)
    }
}

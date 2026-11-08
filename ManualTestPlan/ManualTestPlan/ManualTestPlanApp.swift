//
//  ManualTestPlanApp.swift
//  ManualTestPlan
//

import SwiftUI

@main
struct ManualTestPlanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel(notifier: PlanNotifier())

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarLabel(delegate: delegate)
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Test Plan", for: String.self) { $planID in
            if let planID {
                PlanWindow(planID: planID)
                    .environment(model)
            }
        }
        .windowLevel(model.keepPlanWindowsOnTop ? .floating : .normal)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 720, height: 800)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

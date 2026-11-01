//
//  LaunchAtLogin.swift
//  ManualTestPlan
//

import Foundation
import Observation
import ServiceManagement

/// Registers the app as a login item so the MCP server is already running when an agent first calls it.
@MainActor
@Observable
final class LaunchAtLogin {
    /// Whether the app will start at login.
    private(set) var isEnabled: Bool

    /// True when the system is waiting for the user to approve the login item in System Settings.
    private(set) var needsApproval: Bool

    /// The last failure, for display next to the toggle.
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: SMAppService

    /// Creates the controller.
    /// - Parameter service: The service to manage; defaults to the main app.
    init(service: SMAppService = .mainApp) {
        self.service = service
        self.isEnabled = service.status == .enabled
        self.needsApproval = service.status == .requiresApproval
    }

    /// Turns launch-at-login on or off and refreshes the published state.
    /// - Parameter enabled: The desired state.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Re-reads the system's state, which the user can change in System Settings at any time.
    func refresh() {
        isEnabled = service.status == .enabled
        needsApproval = service.status == .requiresApproval
    }
}

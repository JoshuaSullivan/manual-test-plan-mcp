//
//  AppModel.swift
//  ManualTestPlan
//

import Foundation
import Observation

/// Owns the long-lived objects of the app and wires them together: the plan store, the MCP router and tools
/// that operate on it, and the HTTP server that exposes them to agents.
@MainActor
@Observable
final class AppModel {
    /// The port used until the user picks another.
    nonisolated static let defaultPort: UInt16 = 47821

    private nonisolated static let portDefaultsKey = "serverPort"

    /// All active plans.
    let store: PlanStore
    /// The MCP endpoint's listener.
    let server: MCPServer
    /// Whether the app starts when the user logs in.
    let launchAtLogin: LaunchAtLogin

    /// The port the server listens on (or will, once started).
    private(set) var port: UInt16

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let notifier: (any PlanNotifying)?

    /// Creates the object graph.
    /// - Parameters:
    ///   - store: The plan store. Tests and previews pass one rooted in a temporary directory.
    ///   - defaults: Where settings are persisted.
    ///   - notifier: Announces new plans to the user. Nil (the default) disables notifications, which keeps
    ///     tests and previews from touching the system notification center.
    ///   - launchAtLogin: Manages the login item.
    init(
        store: PlanStore = PlanStore(),
        defaults: UserDefaults = .standard,
        notifier: (any PlanNotifying)? = nil,
        launchAtLogin: LaunchAtLogin = LaunchAtLogin()
    ) {
        self.store = store
        self.defaults = defaults
        self.notifier = notifier
        self.launchAtLogin = launchAtLogin
        let saved = defaults.integer(forKey: Self.portDefaultsKey)
        self.port = UInt16(exactly: saved).flatMap { $0 >= Self.minimumPort ? $0 : nil } ?? Self.defaultPort
        self.server = MCPServer(router: MCPRouter(tools: PlanTools(store: store)))

        if let notifier {
            store.onPlanCreated = { plan in
                Task { await notifier.planCreated(plan) }
            }
            notifier.onOpenPlan = { [store] planID in
                store.requestWindow(for: planID)
            }
        }
    }

    /// Lowest port the user may choose; below this are privileged ports.
    nonisolated static let minimumPort: UInt16 = 1024

    /// Loads saved plans, then starts the server. Safe to call repeatedly; only the first call acts.
    ///
    /// Plans are loaded first so an agent can't create a plan that the initial disk read then overwrites.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await store.load()
        server.start(port: port)
    }

    /// Whether a port number is acceptable for the server.
    /// - Parameter value: The candidate port.
    nonisolated static func isValid(port value: Int) -> Bool {
        (Int(minimumPort)...Int(UInt16.max)).contains(value)
    }

    /// Saves a new port and restarts the server on it.
    /// - Parameter newPort: The port to use. Ignored if invalid or unchanged while running.
    func changePort(to newPort: Int) {
        guard Self.isValid(port: newPort), let value = UInt16(exactly: newPort) else { return }
        guard value != port || server.state != .running(port: value) else { return }
        port = value
        defaults.set(Int(value), forKey: Self.portDefaultsKey)
        server.start(port: value)
    }

    /// The shell command that registers this server with Claude Code.
    var setupCommand: String {
        "claude mcp add --transport http manualtestplan http://127.0.0.1:\(port)/mcp"
    }

    /// Plans that still have steps awaiting the user's verdict.
    var plansNeedingAttention: [TestPlan] {
        store.plans.filter { $0.progress.pending > 0 }
    }
}

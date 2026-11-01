//
//  MCPSessionStore.swift
//  ManualTestPlan
//

import Foundation

/// Remembers which client opened each MCP session, so plans can show which agent created them.
///
/// Sessions live only in memory. A request carrying an unknown or missing session ID is still served,
/// just anonymously: plans outlive app restarts, and an agent that is mid-task when the app relaunches
/// shouldn't be forced to reconnect.
actor MCPSessionStore {
    private var clientNames: [String: String] = [:]
    private var order: [String] = []
    private let limit: Int

    /// Creates a store.
    /// - Parameter limit: The most sessions to remember; the oldest are forgotten first.
    init(limit: Int = 200) {
        self.limit = limit
    }

    /// Registers a new session.
    /// - Parameter clientName: The client's name from `initialize`, if provided.
    /// - Returns: A new session ID for the `Mcp-Session-Id` header.
    func createSession(clientName: String?) -> String {
        let id = UUID().uuidString
        clientNames[id] = clientName ?? ""
        order.append(id)
        while order.count > limit {
            clientNames.removeValue(forKey: order.removeFirst())
        }
        return id
    }

    /// The client name recorded for a session.
    /// - Parameter sessionID: The `Mcp-Session-Id` header value, if any.
    func clientName(for sessionID: String?) -> String? {
        guard let sessionID, let name = clientNames[sessionID], !name.isEmpty else { return nil }
        return name
    }

    /// Forgets a session (HTTP `DELETE`).
    /// - Parameter sessionID: The session to end.
    func endSession(_ sessionID: String) {
        clientNames.removeValue(forKey: sessionID)
        order.removeAll { $0 == sessionID }
    }
}

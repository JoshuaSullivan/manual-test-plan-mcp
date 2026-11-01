//
//  ServerStatusRow.swift
//  ManualTestPlan
//

import SwiftUI

/// Shows whether the MCP server is accepting connections, and why not if it isn't.
struct ServerStatusRow: View {
    let state: MCPServer.State

    var body: some View {
        switch state {
        case .running(let port):
            Label {
                Text("Listening on port \(port, format: .number.grouping(.never))")
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption)
        case .starting:
            Label("Starting…", systemImage: "circle.dotted")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .stopped:
            Label("Server stopped", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

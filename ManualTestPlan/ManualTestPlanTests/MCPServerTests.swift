//
//  MCPServerTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

/// Exercises the listener's lifecycle on real loopback ports.
///
/// The test host is sandboxed without the outbound-network entitlement (the shipping app never makes
/// outbound connections), so these tests can't act as an HTTP client. Request/response behavior is
/// covered by `HTTPRequestParserTests` and `MCPHTTPHandlerTests`; wire-level behavior against the running
/// app is covered by `Scripts/smoke-test.sh`.
@MainActor
struct MCPServerTests {
    private func randomPort() -> UInt16 { UInt16.random(in: 49_152...60_000) }

    /// Waits up to five seconds for the server to leave `.starting`.
    private func settle(_ server: MCPServer) async {
        for _ in 0..<100 where server.state == .starting {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Starts a server on a free random port, retrying if a port happens to be taken.
    private func startOnFreePort(_ server: MCPServer) async throws -> UInt16 {
        for _ in 0..<10 {
            let port = randomPort()
            server.start(port: port)
            await settle(server)
            if server.state == .running(port: port) { return port }
        }
        throw TestError.noFreePort
    }

    private enum TestError: Error { case noFreePort }

    @Test func reportsRunningOnceBound() async throws {
        try await MCPHarness.run { harness in
            let server = MCPServer(router: harness.router)
            defer { server.stop() }
            #expect(server.state == .stopped)

            let port = try await startOnFreePort(server)
            #expect(server.state == .running(port: port))
        }
    }

    @Test func reportsAPortThatIsAlreadyInUse() async throws {
        try await MCPHarness.run { harness in
            let first = MCPServer(router: harness.router)
            let second = MCPServer(router: harness.router)
            defer {
                first.stop()
                second.stop()
            }
            let port = try await startOnFreePort(first)

            second.start(port: port)
            await settle(second)

            guard case .failed(let message) = second.state else {
                Issue.record("expected failure, got \(second.state)")
                return
            }
            #expect(message.contains("\(port)"))
            #expect(first.state == .running(port: port))
        }
    }

    @Test func stopFreesThePortForReuse() async throws {
        try await MCPHarness.run { harness in
            let first = MCPServer(router: harness.router)
            let port = try await startOnFreePort(first)

            first.stop()
            #expect(first.state == .stopped)
            try await Task.sleep(for: .milliseconds(300))

            let second = MCPServer(router: harness.router)
            defer { second.stop() }
            second.start(port: port)
            await settle(second)
            #expect(second.state == .running(port: port))
        }
    }

    @Test func restartingMovesToTheNewPort() async throws {
        try await MCPHarness.run { harness in
            let server = MCPServer(router: harness.router)
            defer { server.stop() }
            _ = try await startOnFreePort(server)
            let second = try await startOnFreePort(server)

            #expect(server.state == .running(port: second))
        }
    }
}

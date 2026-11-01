//
//  MCPHTTPHandlerTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

@MainActor
struct MCPHTTPHandlerTests {
    private static let port: UInt16 = 47821

    private func withHandler(_ body: (MCPHTTPHandler, MCPHarness) async throws -> Void) async throws {
        try await MCPHarness.run { harness in
            try await body(MCPHTTPHandler(router: harness.router, port: Self.port), harness)
        }
    }

    private func request(
        _ method: String = "POST",
        path: String = "/mcp",
        host: String? = "127.0.0.1:\(MCPHTTPHandlerTests.port)",
        headers: [String: String] = [:],
        body: String = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
    ) -> HTTPRequest {
        var all = headers
        if let host { all["host"] = host }
        return HTTPRequest(method: method, target: path, headers: all, body: Data(body.utf8))
    }

    @Test func postRoutesToTheRouter() async throws {
        try await withHandler { handler, _ in
            let response = await handler.handle(request())
            #expect(response.status == 200)
            #expect(response.headers["Content-Type"] == "application/json")
            #expect(MCPHarness.decode(response.body)["result"] == [:])
        }
    }

    @Test func initializeReturnsTheSessionHeader() async throws {
        try await withHandler { handler, _ in
            let response = await handler.handle(request(
                body: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"X"}}}"#
            ))
            #expect(response.headers["Mcp-Session-Id"]?.isEmpty == false)
        }
    }

    @Test func notificationsReturn202WithNoBody() async throws {
        try await withHandler { handler, _ in
            let response = await handler.handle(request(body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
            #expect(response.status == 202)
            #expect(response.body.isEmpty)
            #expect(response.headers["Content-Type"] == nil)
        }
    }

    @Test(arguments: ["127.0.0.1:47821", "localhost:47821", "LOCALHOST:47821", "[::1]:47821"])
    func acceptsLoopbackHosts(host: String) async throws {
        try await withHandler { handler, _ in
            #expect(await handler.handle(request(host: host)).status == 200)
        }
    }

    @Test(arguments: ["evil.example:47821", "127.0.0.1:1", "127.0.0.1", "localhost", "10.0.0.5:47821", ""])
    func rejectsOtherHosts(host: String) async throws {
        try await withHandler { handler, _ in
            #expect(await handler.handle(request(host: host)).status == 403)
        }
    }

    @Test func rejectsMissingHost() async throws {
        try await withHandler { handler, _ in
            #expect(await handler.handle(request(host: nil)).status == 403)
        }
    }

    @Test func rejectsAnyOriginHeader() async throws {
        try await withHandler { handler, harness in
            for origin in ["https://evil.example", "http://localhost:3000", "null"] {
                let response = await handler.handle(request(headers: ["origin": origin]))
                #expect(response.status == 403, "\(origin)")
            }
            #expect(harness.store.plans.isEmpty)
        }
    }

    @Test func otherPathsAre404() async throws {
        try await withHandler { handler, _ in
            #expect(await handler.handle(request(path: "/")).status == 404)
            #expect(await handler.handle(request(path: "/mcp/extra")).status == 404)
            #expect(await handler.handle(request(path: "/mcp?x=1")).status == 200)
        }
    }

    @Test func unsupportedMethodsAre405() async throws {
        try await withHandler { handler, _ in
            for method in ["GET", "PUT", "OPTIONS", "PATCH"] {
                let response = await handler.handle(request(method))
                #expect(response.status == 405, "\(method)")
                #expect(response.headers["Allow"] == "POST, DELETE")
            }
        }
    }

    @Test func emptyPostBodyIs400() async throws {
        try await withHandler { handler, _ in
            #expect(await handler.handle(request(body: "")).status == 400)
        }
    }

    @Test func deleteEndsTheSession() async throws {
        try await withHandler { handler, harness in
            let initialize = await handler.handle(request(
                body: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"X"}}}"#
            ))
            let sessionID = try #require(initialize.headers["Mcp-Session-Id"])

            let deleted = await handler.handle(request("DELETE", headers: ["mcp-session-id": sessionID], body: ""))
            #expect(deleted.status == 200)

            let created = await harness.createSamplePlan(sessionID: sessionID)
            let planID = try #require(created["plan_id"]?.stringValue)
            #expect(harness.store.plan(id: planID)?.agentName == nil)
        }
    }
}

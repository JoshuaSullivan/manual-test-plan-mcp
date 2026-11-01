//
//  MCPRouterTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

@MainActor
struct MCPRouterTests {
    @Test func initializeNegotiatesVersionAndCreatesSession() async throws {
        try await MCPHarness.run { harness in
            let response = await harness.send("initialize", params: [
                "protocolVersion": "2025-06-18",
                "clientInfo": ["name": "Test Agent", "version": "1"],
                "capabilities": [:]
            ])
            let envelope = MCPHarness.decode(response.body)
            let result = try #require(envelope["result"])

            #expect(response.status == 200)
            #expect(response.sessionID?.isEmpty == false)
            #expect(envelope["jsonrpc"]?.stringValue == "2.0")
            #expect(result["protocolVersion"]?.stringValue == "2025-06-18")
            #expect(result["serverInfo"]?["name"]?.stringValue == "ManualTestPlan")
            #expect(result["capabilities"]?["tools"] != nil)
            #expect(result["instructions"]?.stringValue?.contains("create_test_plan") == true)
        }
    }

    @Test func initializeFallsBackToNewestSupportedVersion() async throws {
        try await MCPHarness.run { harness in
            let result = await harness.rpc("initialize", params: ["protocolVersion": "1999-01-01"])["result"]
            #expect(result?["protocolVersion"]?.stringValue == MCPRouter.supportedProtocolVersions[0])
        }
    }

    @Test func notificationsAreAcceptedWithoutABody() async throws {
        try await MCPHarness.run { harness in
            let notification: JSONValue = ["jsonrpc": "2.0", "method": "notifications/initialized"]
            let response = await harness.router.handle(body: try JSONEncoder().encode(notification), sessionID: nil)
            #expect(response.status == 202)
            #expect(response.body == nil)
        }
    }

    @Test func pingReturnsEmptyResult() async throws {
        try await MCPHarness.run { harness in
            let envelope = await harness.rpc("ping")
            #expect(envelope["result"] == [:])
            #expect(envelope["id"] == 1)
        }
    }

    @Test func toolsListAdvertisesEveryToolWithAnObjectSchema() async throws {
        try await MCPHarness.run { harness in
            let tools = try #require(await harness.rpc("tools/list")["result"]?["tools"]?.arrayValue)
            let names = tools.compactMap { $0["name"]?.stringValue }

            #expect(names == [
                "create_test_plan", "get_test_plan", "wait_for_test_plan", "get_step_evidence",
                "list_test_plans", "add_to_test_plan", "revise_step", "complete_test_plan"
            ])
            for tool in tools {
                #expect(tool["description"]?.stringValue?.isEmpty == false)
                #expect(tool["inputSchema"]?["type"]?.stringValue == "object")
                #expect(tool["inputSchema"]?["properties"]?.objectValue != nil)
            }
        }
    }

    @Test func unknownMethodIsAJSONRPCError() async throws {
        try await MCPHarness.run { harness in
            let error = await harness.rpc("resources/list")["error"]
            #expect(error?["code"] == -32601)
        }
    }

    @Test func malformedBodiesAreRejected() async throws {
        try await MCPHarness.run { harness in
            let garbage = await harness.router.handle(body: Data("{nope".utf8), sessionID: nil)
            #expect(garbage.status == 400)
            #expect(MCPHarness.decode(garbage.body)["error"]?["code"] == -32700)

            let batch = await harness.router.handle(body: Data("[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}]".utf8), sessionID: nil)
            #expect(batch.status == 400)
            #expect(MCPHarness.decode(batch.body)["error"]?["code"] == -32600)
        }
    }

    @Test func callingAnUnknownToolIsAProtocolError() async throws {
        try await MCPHarness.run { harness in
            let unknown = await harness.rpc("tools/call", params: ["name": "nope"])
            #expect(unknown["error"]?["code"] == -32602)
            let missing = await harness.rpc("tools/call", params: [:])
            #expect(missing["error"]?["code"] == -32602)
        }
    }

    @Test func clientNameFromInitializeIsAttachedToCreatedPlans() async throws {
        try await MCPHarness.run { harness in
            let response = await harness.send("initialize", params: ["clientInfo": ["name": "Test Agent"]])
            let sessionID = try #require(response.sessionID)

            let created = await harness.createSamplePlan(sessionID: sessionID)
            let planID = try #require(created["plan_id"]?.stringValue)
            #expect(harness.store.plan(id: planID)?.agentName == "Test Agent")

            // Unknown or missing sessions are served anonymously.
            let anonymous = await harness.createSamplePlan(sessionID: "stale-session")
            let anonymousID = try #require(anonymous["plan_id"]?.stringValue)
            #expect(harness.store.plan(id: anonymousID)?.agentName == nil)
        }
    }

    @Test func endedSessionsAreForgotten() async throws {
        try await MCPHarness.run { harness in
            let response = await harness.send("initialize", params: ["clientInfo": ["name": "Test Agent"]])
            let sessionID = try #require(response.sessionID)
            await harness.router.endSession(sessionID)

            let created = await harness.createSamplePlan(sessionID: sessionID)
            let planID = try #require(created["plan_id"]?.stringValue)
            #expect(harness.store.plan(id: planID)?.agentName == nil)
        }
    }
}

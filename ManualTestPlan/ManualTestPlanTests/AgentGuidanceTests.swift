//
//  AgentGuidanceTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

/// The text agents read is the only thing that tells them to alert the user that a window opened, and
/// plan windows can open behind other windows, so this guidance is behavior worth protecting.
@MainActor
struct AgentGuidanceTests {
    @Test func serverInstructionsTellAgentsToAnnounceTheWindow() async throws {
        try await MCPHarness.run { harness in
            let result = await harness.rpc("initialize")["result"]
            let instructions = try #require(result?["instructions"]?.stringValue)

            #expect(instructions.contains("Tell the user"))
            #expect(instructions.contains("behind"))
            #expect(instructions.contains("menu bar"))
        }
    }

    @Test func createToolDescriptionTellsAgentsToAnnounceTheWindow() async throws {
        try await MCPHarness.run { harness in
            let tools = try #require(await harness.rpc("tools/list")["result"]?["tools"]?.arrayValue)
            let create = try #require(tools.first { $0["name"]?.stringValue == "create_test_plan" })
            let description = try #require(create["description"]?.stringValue)

            #expect(description.contains("behind other windows"))
            #expect(description.contains("tell the user"))
        }
    }

    @Test func createReplyNamesTheWindowAndTellsAgentsHowToHelpTheUserFindIt() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let message = try #require(created["message"]?.stringValue)

            #expect(message.contains("Kanban board"))
            #expect(message.contains("behind other windows"))
            #expect(message.contains("tell the user"))
            #expect(message.contains("menu bar"))
            #expect(message.contains("wait_for_test_plan"))
        }
    }
}

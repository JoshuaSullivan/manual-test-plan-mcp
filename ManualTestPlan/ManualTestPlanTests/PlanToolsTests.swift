//
//  PlanToolsTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

@MainActor
struct PlanToolsTests {
    // MARK: - create_test_plan

    @Test func createReturnsIDsForEveryCaseAndStep() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let cases = try #require(created["cases"]?.arrayValue)

            #expect(planID.hasPrefix("tp_"))
            #expect(cases.count == 2)
            #expect(cases[0]["steps"]?.arrayValue?.count == 2)
            #expect(cases[0]["case_id"]?.stringValue == harness.store.plan(id: planID)?.cases[0].id)
            #expect(harness.store.plan(id: planID)?.cases[0].steps[0].expected == "A is below B")
            #expect(harness.store.windowRequests == [planID])
        }
    }

    nonisolated struct InvalidCreate: Sendable, CustomTestStringConvertible {
        var label: String
        var arguments: JSONValue
        var expectedFragment: String
        var testDescription: String { label }
    }

    nonisolated static let invalidCreates: [InvalidCreate] = [
        InvalidCreate(
            label: "empty title",
            arguments: ["title": "  ", "cases": [["title": "C", "steps": [["instruction": "x"]]]]],
            expectedFragment: "'title'"
        ),
        InvalidCreate(label: "no cases", arguments: ["title": "T", "cases": []], expectedFragment: "at least one test case"),
        InvalidCreate(
            label: "case without steps",
            arguments: ["title": "T", "cases": [["title": "C", "steps": []]]],
            expectedFragment: "at least one step"
        ),
        InvalidCreate(
            label: "blank instruction",
            arguments: ["title": "T", "cases": [["title": "C", "steps": [["instruction": ""]]]]],
            expectedFragment: "'instruction'"
        ),
        InvalidCreate(label: "missing cases", arguments: ["title": "T"], expectedFragment: "missing required field 'cases'"),
        InvalidCreate(
            label: "nested missing field",
            arguments: ["title": "T", "cases": [["title": "C", "steps": [["expected": "x"]]]]],
            expectedFragment: "cases[0].steps[0].instruction"
        ),
        InvalidCreate(label: "wrong type", arguments: ["title": 5, "cases": []], expectedFragment: "title")
    ]

    @Test(arguments: invalidCreates)
    func createRejectsInvalidInput(_ scenario: InvalidCreate) async throws {
        try await MCPHarness.run { harness in
            let reply = await harness.call("create_test_plan", scenario.arguments)
            #expect(reply.isError)
            #expect(reply.text.contains(scenario.expectedFragment), "got: \(reply.text)")
            #expect(harness.store.plans.isEmpty)
        }
    }

    // MARK: - get_test_plan

    @Test func getSummaryListsOnlyActionableSteps() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let plan = try #require(harness.store.plan(id: planID))
            let steps = plan.cases.flatMap(\.steps)
            try harness.store.setStatus(.passed, forStep: steps[0].id, inPlan: planID)
            try harness.store.setStatus(.failed, forStep: steps[1].id, inPlan: planID)
            try harness.store.setNote("Relaunch lost the order", forStep: steps[1].id, inPlan: planID)
            try harness.store.setStatus(.blocked, forStep: steps[2].id, inPlan: planID)

            let summary = await harness.call("get_test_plan", ["plan_id": .string(planID)]).json
            #expect(summary["status"]?.stringValue == "failed")
            #expect(summary["resolved"]?.boolValue == true)
            #expect(summary["revision"] == 3)
            #expect(summary["progress"]?["passed"] == 1)
            #expect(summary["progress"]?["failed"] == 1)
            #expect(summary["progress"]?["blocked"] == 1)
            let reorderSteps = summary["cases"]?.arrayValue?[0]["steps"]?.arrayValue
            #expect(reorderSteps?.count == 1)
            #expect(reorderSteps?[0]["note"]?.stringValue == "Relaunch lost the order")
            #expect(reorderSteps?[0]["status"]?.stringValue == "failed")

            let full = await harness.call("get_test_plan", ["plan_id": .string(planID), "detail": "full"]).json
            #expect(full["cases"]?.arrayValue?[0]["steps"]?.arrayValue?.count == 2)
        }
    }

    @Test func getForUnknownPlanExplainsHowToRecover() async throws {
        try await MCPHarness.run { harness in
            let reply = await harness.call("get_test_plan", ["plan_id": "tp_nope"])
            #expect(reply.isError)
            #expect(reply.text.contains("list_test_plans"))
        }
    }

    // MARK: - wait_for_test_plan

    @Test func waitReturnsAsSoonAsTheUserRecordsAVerdict() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)

            let clock = ContinuousClock()
            let start = clock.now
            async let reply = harness.call("wait_for_test_plan", ["plan_id": .string(planID), "timeout_seconds": 30])
            try await Task.sleep(for: .milliseconds(100))
            try harness.store.setStatus(.passed, forStep: stepID, inPlan: planID)

            let result = await reply.json
            #expect(clock.now - start < .seconds(10))
            #expect(result["changed"]?.boolValue == true)
            #expect(result["timed_out"]?.boolValue == false)
            #expect(result["plan"]?["revision"] == 1)
            #expect(result["hint"]?.stringValue?.contains("since_revision=1") == true)
        }
    }

    @Test func waitTimesOutWhenNothingChanges() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)

            let result = await harness.call("wait_for_test_plan", ["plan_id": .string(planID), "timeout_seconds": 1]).json
            #expect(result["changed"]?.boolValue == false)
            #expect(result["timed_out"]?.boolValue == true)
        }
    }

    @Test func waitWithAStaleRevisionReturnsImmediately() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)
            try harness.store.setStatus(.passed, forStep: stepID, inPlan: planID)

            let clock = ContinuousClock()
            let start = clock.now
            let result = await harness.call("wait_for_test_plan", ["plan_id": .string(planID), "since_revision": 0, "timeout_seconds": 30]).json
            #expect(clock.now - start < .seconds(5))
            #expect(result["changed"]?.boolValue == true)
        }
    }

    @Test func waitTellsTheAgentWhenEverythingIsResolved() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            for step in try #require(harness.store.plan(id: planID)).cases.flatMap(\.steps) {
                try harness.store.setStatus(.passed, forStep: step.id, inPlan: planID)
            }

            let result = await harness.call("wait_for_test_plan", ["plan_id": .string(planID), "since_revision": 0]).json
            #expect(result["plan"]?["resolved"]?.boolValue == true)
            #expect(result["hint"]?.stringValue?.contains("complete_test_plan") == true)
        }
    }

    // MARK: - get_step_evidence

    @Test func evidenceIsReturnedAsImageContent() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)
            let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
            try await harness.store.addEvidence(png, toStep: stepID, inPlan: planID)

            let reply = await harness.call("get_step_evidence", ["plan_id": .string(planID), "step_id": .string(stepID)])
            #expect(!reply.isError)
            #expect(reply.json["evidence_count"] == 1)
            #expect(reply.images == [png])
            #expect(reply.content.last?["mimeType"]?.stringValue == "image/png")
        }
    }

    @Test func evidenceForAStepWithoutAnyReturnsJustTheStep() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)

            let reply = await harness.call("get_step_evidence", ["plan_id": .string(planID), "step_id": .string(stepID)])
            #expect(!reply.isError)
            #expect(reply.images.isEmpty)
            #expect(reply.json["evidence_count"] == 0)
        }
    }

    // MARK: - list_test_plans

    @Test func listFiltersByKeyword() async throws {
        try await MCPHarness.run { harness in
            let kanban = await harness.createSamplePlan()
            _ = await harness.call("create_test_plan", [
                "title": "Settings", "cases": [["title": "Dark mode", "steps": [["instruction": "Toggle appearance"]]]]
            ])

            let all = await harness.call("list_test_plans").json.arrayValue
            #expect(all?.count == 2)

            let filtered = await harness.call("list_test_plans", ["query": "appearance"]).json.arrayValue
            #expect(filtered?.count == 1)
            #expect(filtered?[0]["title"]?.stringValue == "Settings")

            let byID = await harness.call("list_test_plans", ["query": kanban["plan_id"] ?? ""]).json.arrayValue
            #expect(byID?.first?["title"]?.stringValue == "Kanban board")
        }
    }

    // MARK: - add_to_test_plan

    @Test func addAppendsCasesOrSteps() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let caseID = try #require(created["cases"]?.arrayValue?[0]["case_id"]?.stringValue)

            let addedCase = await harness.call("add_to_test_plan", [
                "plan_id": .string(planID),
                "cases": [["title": "Extra", "steps": [["instruction": "Look"]]]]
            ])
            #expect(!addedCase.isError)
            #expect(addedCase.json["cases"]?.arrayValue?.count == 1)

            let addedStep = await harness.call("add_to_test_plan", [
                "plan_id": .string(planID), "case_id": .string(caseID), "steps": [["instruction": "Again"]]
            ])
            #expect(!addedStep.isError)
            #expect(addedStep.json["steps"]?.arrayValue?.count == 1)

            let plan = try #require(harness.store.plan(id: planID))
            #expect(plan.cases.map(\.title) == ["Reorder", "Cancel", "Extra"])
            #expect(plan.cases[0].steps.last?.instruction == "Again")
        }
    }

    @Test func addRejectsAmbiguousOrEmptyRequests() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let caseID = try #require(created["cases"]?.arrayValue?[0]["case_id"]?.stringValue)
            let newCase: JSONValue = [["title": "Extra", "steps": [["instruction": "Look"]]]]

            #expect(await harness.call("add_to_test_plan", ["plan_id": .string(planID)]).isError)
            #expect(await harness.call("add_to_test_plan", [
                "plan_id": .string(planID), "cases": newCase, "case_id": .string(caseID), "steps": [["instruction": "x"]]
            ]).isError)
            #expect(await harness.call("add_to_test_plan", [
                "plan_id": .string(planID), "case_id": "tc_nope", "steps": [["instruction": "x"]]
            ]).text.contains("tc_nope"))
            #expect(harness.store.plan(id: planID)?.cases.count == 2)
        }
    }

    // MARK: - revise_step

    @Test func reviseResetsTheStepAndKeepsTheUsersNote() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)
            try harness.store.setStatus(.blocked, forStep: stepID, inPlan: planID)
            try harness.store.setNote("No such card", forStep: stepID, inPlan: planID)

            let reply = await harness.call("revise_step", [
                "plan_id": .string(planID), "step_id": .string(stepID), "instruction": "Drag the first card down"
            ])
            #expect(!reply.isError)
            #expect(reply.json["status"]?.stringValue == "pending")
            #expect(reply.json["instruction"]?.stringValue == "Drag the first card down")
            #expect(reply.json["expected"]?.stringValue == "A is below B")
            #expect(reply.json["note"]?.stringValue == "No such card")

            let nothing = await harness.call("revise_step", ["plan_id": .string(planID), "step_id": .string(stepID)])
            #expect(nothing.isError)
        }
    }

    // MARK: - complete_test_plan

    @Test func completeRefusesPendingStepsUnlessForced() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)

            let refused = await harness.call("complete_test_plan", ["plan_id": .string(planID)])
            #expect(refused.isError)
            #expect(refused.text.contains("force=true"))
            #expect(harness.store.plan(id: planID) != nil)

            let forced = await harness.call("complete_test_plan", ["plan_id": .string(planID), "force": true])
            #expect(!forced.isError)
            #expect(harness.store.plan(id: planID) == nil)
        }
    }

    @Test func completeReturnsAReportThenDeletesEverything() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let steps = try #require(harness.store.plan(id: planID)).cases.flatMap(\.steps)
            try harness.store.setStatus(.passed, forStep: steps[0].id, inPlan: planID)
            try harness.store.setStatus(.failed, forStep: steps[1].id, inPlan: planID)
            try harness.store.setNote("Order lost", forStep: steps[1].id, inPlan: planID)
            try harness.store.setStatus(.passed, forStep: steps[2].id, inPlan: planID)
            try await harness.store.addEvidence(Data([1]), toStep: steps[1].id, inPlan: planID)

            let reply = await harness.call("complete_test_plan", ["plan_id": .string(planID)])

            #expect(!reply.isError)
            #expect(reply.text.contains("# Kanban board"))
            #expect(reply.text.contains("**Result: FAIL**"))
            #expect(reply.text.contains("Note: Order lost"))
            #expect(reply.text.contains("1 screenshot(s) attached"))
            #expect(reply.text.contains(steps[1].id))
            #expect(!FileManager.default.fileExists(atPath: harness.root.appending(path: planID).path(percentEncoded: false)))

            let afterwards = await harness.call("get_test_plan", ["plan_id": .string(planID)])
            #expect(afterwards.isError)
        }
    }
}

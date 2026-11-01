//
//  PlanStoreTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

@MainActor
struct PlanStoreTests {
    private func withStore(_ body: (PlanStore, URL) async throws -> Void) async throws {
        let root = URL.temporaryDirectory.appending(path: "ManualTestPlanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlanStore(persistence: PlanPersistence(rootDirectory: root))
        await store.load()
        try await body(store, root)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func sampleCases() -> [TestCase] {
        [
            TestCase(title: "Reorder cards", preconditions: "Board has two cards", steps: [
                TestStep(instruction: "Drag card A below card B", expected: "A is below B"),
                TestStep(instruction: "Relaunch the app")
            ]),
            TestCase(title: "Cancel drag", steps: [TestStep(instruction: "Press Escape mid-drag")])
        ]
    }

    // MARK: - Create and persist

    @Test func createdPlanIsPersistedAndRequestsAWindow() async throws {
        try await withStore { store, root in
            let plan = store.createPlan(title: "Kanban", agentName: "claude-code", cases: sampleCases())
            await store.flushPendingSaves()

            #expect(store.plan(id: plan.id) == plan)
            #expect(store.windowRequests == [plan.id])
            let reloaded = await PlanPersistence(rootDirectory: root).loadAll()
            #expect(reloaded == [plan])
        }
    }

    @Test func userChangesSurviveRelaunch() async throws {
        try await withStore { store, root in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            let stepID = plan.cases[0].steps[0].id
            try store.setStatus(.failed, forStep: stepID, inPlan: plan.id)
            try store.setNote("Snapped back", forStep: stepID, inPlan: plan.id)
            await store.flushPendingSaves()

            let relaunched = PlanStore(persistence: PlanPersistence(rootDirectory: root))
            await relaunched.load()
            let step = try #require(relaunched.plan(id: plan.id)?.step(withID: stepID))
            #expect(step.status == .failed)
            #expect(step.note == "Snapped back")
        }
    }

    // MARK: - Errors

    @Test func unknownIdentifiersThrow() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            #expect(throws: PlanStoreError.planNotFound("tp_nope")) {
                try store.setStatus(.passed, forStep: "st_x", inPlan: "tp_nope")
            }
            #expect(throws: PlanStoreError.stepNotFound("st_nope")) {
                try store.setStatus(.passed, forStep: "st_nope", inPlan: plan.id)
            }
            #expect(throws: PlanStoreError.caseNotFound("tc_nope")) {
                try store.appendSteps([TestStep(instruction: "x")], toCase: "tc_nope", inPlan: plan.id)
            }
        }
    }

    // MARK: - Agent edits

    @Test func appendingCasesAndSteps() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            try store.appendCases([TestCase(title: "Extra", steps: [TestStep(instruction: "Look")])], toPlan: plan.id)
            try store.appendSteps([TestStep(instruction: "Again")], toCase: plan.cases[0].id, inPlan: plan.id)

            let updated = try #require(store.plan(id: plan.id))
            #expect(updated.cases.map(\.title) == ["Reorder cards", "Cancel drag", "Extra"])
            #expect(updated.cases[0].steps.count == 3)
            #expect(updated.cases[0].steps[0].id == plan.cases[0].steps[0].id)
        }
    }

    @Test func revisingAStepResetsStatusButKeepsUserInput() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            let stepID = plan.cases[0].steps[0].id
            try store.setStatus(.blocked, forStep: stepID, inPlan: plan.id)
            try store.setNote("No such button", forStep: stepID, inPlan: plan.id)

            try store.reviseStep(stepID, inPlan: plan.id, instruction: "Drag card A using its handle", expected: nil)

            let step = try #require(store.plan(id: plan.id)?.step(withID: stepID))
            #expect(step.status == .pending)
            #expect(step.instruction == "Drag card A using its handle")
            #expect(step.expected == "A is below B")
            #expect(step.note == "No such button")
        }
    }

    // MARK: - Completion

    @Test func completingWithPendingStepsRequiresForce() async throws {
        try await withStore { store, root in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            try store.setStatus(.passed, forStep: plan.cases[0].steps[0].id, inPlan: plan.id)

            await #expect(throws: PlanStoreError.unresolvedSteps([plan.cases[0].steps[1].id, plan.cases[1].steps[0].id])) {
                try await store.complete(planID: plan.id, force: false)
            }
            #expect(store.plan(id: plan.id) != nil)

            let report = try await store.complete(planID: plan.id, force: true)
            #expect(report.id == plan.id)
            #expect(store.plan(id: plan.id) == nil)
            #expect(!exists(root.appending(path: plan.id)))
        }
    }

    @Test func completingDeletesPlanDirectoryAndEvidence() async throws {
        try await withStore { store, root in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            for step in plan.cases.flatMap(\.steps) {
                try store.setStatus(.passed, forStep: step.id, inPlan: plan.id)
            }
            let stepID = plan.cases[0].steps[0].id
            try await store.addEvidence(Data([1, 2, 3]), named: "shot.png", toStep: stepID, inPlan: plan.id)
            let image = try #require(store.plan(id: plan.id)?.step(withID: stepID)?.evidence.first)
            let evidenceFile = root.appending(path: "\(plan.id)/evidence/\(image.storedFilename)")
            #expect(exists(evidenceFile))

            let report = try await store.complete(planID: plan.id, force: false)

            #expect(report.step(withID: stepID)?.evidence == [image])
            #expect(!exists(evidenceFile))
            #expect(!exists(root.appending(path: plan.id)))
            #expect(store.windowRequests.isEmpty)

            // A late debounced save must not resurrect the directory.
            await store.flushPendingSaves()
            #expect(!exists(root.appending(path: plan.id)))
            #expect(await PlanPersistence(rootDirectory: root).loadAll().isEmpty)
        }
    }

    @Test func completedPlanCannotBeMutatedOrCompletedAgain() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            _ = try await store.complete(planID: plan.id, force: true)

            #expect(throws: PlanStoreError.planNotFound(plan.id)) {
                try store.setStatus(.passed, forStep: plan.cases[0].steps[0].id, inPlan: plan.id)
            }
            await #expect(throws: PlanStoreError.planNotFound(plan.id)) {
                try await store.complete(planID: plan.id, force: true)
            }
        }
    }

    // MARK: - Evidence

    @Test func removingEvidenceDeletesItsFile() async throws {
        try await withStore { store, root in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            let stepID = plan.cases[0].steps[0].id
            try await store.addEvidence(Data([7]), named: "shot.png", toStep: stepID, inPlan: plan.id)
            let image = try #require(store.plan(id: plan.id)?.step(withID: stepID)?.evidence.first)
            #expect(try await store.evidenceData(for: image, inPlan: plan.id) == Data([7]))

            try await store.removeEvidence(image.id, fromStep: stepID, inPlan: plan.id)

            #expect(store.plan(id: plan.id)?.step(withID: stepID)?.evidence.isEmpty == true)
            #expect(!exists(root.appending(path: "\(plan.id)/evidence/\(image.storedFilename)")))
        }
    }

    @Test func evidenceForUnknownStepLeavesNoFile() async throws {
        try await withStore { store, root in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            await #expect(throws: PlanStoreError.stepNotFound("st_nope")) {
                try await store.addEvidence(Data([1]), named: "shot.png", toStep: "st_nope", inPlan: plan.id)
            }
            #expect(!exists(root.appending(path: "\(plan.id)/evidence")))
        }
    }

    // MARK: - Search

    @Test func searchMatchesAllTermsAcrossFields() async throws {
        try await withStore { store, _ in
            let kanban = store.createPlan(title: "Kanban board", summary: "Drag and drop", cases: sampleCases())
            let settings = store.createPlan(title: "Settings", cases: [
                TestCase(title: "Dark mode", steps: [TestStep(instruction: "Toggle appearance")])
            ])
            try store.setNote("Flickers on RELEASE", forStep: kanban.cases[0].steps[0].id, inPlan: kanban.id)

            #expect(store.search(matching: nil).map(\.id) == [kanban.id, settings.id])
            #expect(store.search(matching: "  ").count == 2)
            #expect(store.search(matching: "kanban").map(\.id) == [kanban.id])
            #expect(store.search(matching: "flickers release").map(\.id) == [kanban.id])
            #expect(store.search(matching: "appearance").map(\.id) == [settings.id])
            #expect(store.search(matching: kanban.id).map(\.id) == [kanban.id])
            #expect(store.search(matching: "kanban appearance").isEmpty)
        }
    }

    // MARK: - Waiting

    @Test func waitReturnsWhenUserSetsAStatus() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            let revision = store.userRevision(of: plan.id)
            let stepID = plan.cases[0].steps[0].id

            let clock = ContinuousClock()
            let waiter = Task { @MainActor in
                await clock.measure {
                    await store.waitForUserChange(planID: plan.id, since: revision, timeout: .seconds(30))
                }
            }
            await Task.yield()
            try store.setStatus(.passed, forStep: stepID, inPlan: plan.id)

            let elapsed = await waiter.value
            #expect(elapsed < .seconds(5))
            #expect(store.userRevision(of: plan.id) == revision + 1)
        }
    }

    @Test func waitReturnsImmediatelyIfAlreadyChanged() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            try store.setStatus(.passed, forStep: plan.cases[0].steps[0].id, inPlan: plan.id)

            let elapsed = await ContinuousClock().measure {
                await store.waitForUserChange(planID: plan.id, since: 0, timeout: .seconds(30))
            }
            #expect(elapsed < .seconds(5))
        }
    }

    @Test func notesAndAgentEditsDoNotWakeWaiters() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            let revision = store.userRevision(of: plan.id)
            let stepID = plan.cases[0].steps[0].id

            let waiter = Task { @MainActor in
                await ContinuousClock().measure {
                    await store.waitForUserChange(planID: plan.id, since: revision, timeout: .milliseconds(400))
                }
            }
            await Task.yield()
            try store.setNote("typing…", forStep: stepID, inPlan: plan.id)
            try store.appendCases([TestCase(title: "More")], toPlan: plan.id)
            try store.reviseStep(stepID, inPlan: plan.id, instruction: "Rewritten", expected: nil)

            let elapsed = await waiter.value
            #expect(elapsed >= .milliseconds(350))
            #expect(store.userRevision(of: plan.id) == revision)
        }
    }

    @Test func waitReturnsWhenPlanIsCompleted() async throws {
        try await withStore { store, _ in
            let plan = store.createPlan(title: "Kanban", cases: sampleCases())
            let revision = store.userRevision(of: plan.id)

            let waiter = Task { @MainActor in
                await ContinuousClock().measure {
                    await store.waitForUserChange(planID: plan.id, since: revision, timeout: .seconds(30))
                }
            }
            await Task.yield()
            _ = try await store.complete(planID: plan.id, force: true)

            #expect(await waiter.value < .seconds(5))
        }
    }
}

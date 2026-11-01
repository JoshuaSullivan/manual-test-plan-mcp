//
//  TestPlanTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

struct TestPlanTests {
    private func makePlan() -> TestPlan {
        TestPlan(
            title: "Drag and drop",
            cases: [
                TestCase(title: "Reorder", steps: [
                    TestStep(instruction: "Drag card A below card B"),
                    TestStep(instruction: "Release", expected: "A is below B")
                ]),
                TestCase(title: "Cancel", steps: [
                    TestStep(instruction: "Drag card A, then press Escape")
                ])
            ]
        )
    }

    @Test func idsHaveExpectedShape() {
        let plan = makePlan()
        #expect(plan.id.hasPrefix("tp_"))
        #expect(plan.id.count == "tp_".count + 6)
        #expect(plan.cases[0].id.hasPrefix("tc_"))
        #expect(plan.cases[0].steps[0].id.hasPrefix("st_"))
    }

    @Test func newPlanIsPendingAndUnresolved() {
        let plan = makePlan()
        #expect(plan.status == .pending)
        #expect(!plan.isResolved)
        #expect(plan.progress.total == 3)
        #expect(plan.progress.pending == 3)
    }

    @Test func emptyPlanIsNeverResolved() {
        #expect(!TestPlan(title: "Empty").isResolved)
    }

    @Test func progressAndStatusFollowSteps() {
        var plan = makePlan()
        plan.cases[0].steps[0].status = .passed
        plan.cases[0].steps[1].status = .passed
        #expect(plan.cases[0].status == .passed)
        #expect(plan.status == .pending)

        plan.cases[1].steps[0].status = .blocked
        #expect(plan.status == .blocked)
        #expect(plan.isResolved)

        plan.cases[0].steps[1].status = .failed
        #expect(plan.cases[0].status == .failed)
        #expect(plan.status == .failed)
        #expect(plan.progress == PlanProgress(pending: 0, passed: 1, failed: 1, blocked: 1))
        #expect(plan.progress.resolved == 3)
    }

    @Test func locatesStepsAcrossCases() throws {
        let plan = makePlan()
        let target = plan.cases[1].steps[0]
        let location = try #require(plan.location(ofStep: target.id))
        #expect(location.caseIndex == 1)
        #expect(location.stepIndex == 0)
        #expect(plan.step(withID: target.id) == target)
        #expect(plan.step(withID: "st_nope") == nil)
    }

    @Test func codableRoundTrip() throws {
        var plan = makePlan()
        plan.cases[0].steps[0].status = .failed
        plan.cases[0].steps[0].note = "Card snapped back"
        plan.cases[0].steps[0].evidence = [EvidenceFile(name: "shot.png", byteCount: 3)]

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(TestPlan.self, from: data)

        #expect(decoded == plan)
    }
}

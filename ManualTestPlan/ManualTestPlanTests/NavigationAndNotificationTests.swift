//
//  NavigationAndNotificationTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

struct StepNavigatorTests {
    private func makePlan() -> TestPlan {
        TestPlan(title: "Nav", cases: [
            TestCase(title: "A", steps: [TestStep(instruction: "a1"), TestStep(instruction: "a2")]),
            TestCase(title: "B", steps: [TestStep(instruction: "b1")]),
            TestCase(title: "Empty")
        ])
    }

    private func judge(_ id: String, _ status: StepStatus, in plan: inout TestPlan) {
        guard let location = plan.location(ofStep: id) else { return }
        plan.cases[location.caseIndex].steps[location.stepIndex].status = status
    }

    @Test func walksStepsAcrossCases() {
        let plan = makePlan()
        let navigator = StepNavigator(plan: plan)
        let ids = plan.cases.flatMap(\.steps).map(\.id)

        #expect(navigator.order == ids)
        #expect(navigator.next(after: ids[0]) == ids[1])
        #expect(navigator.next(after: ids[1]) == ids[2])
        #expect(navigator.next(after: ids[2]) == nil)
        #expect(navigator.previous(before: ids[2]) == ids[1])
        #expect(navigator.previous(before: ids[0]) == nil)
        #expect(navigator.next(after: "st_unknown") == nil)
        #expect(navigator.previous(before: "st_unknown") == nil)
    }

    @Test func findsTheNextPendingStepAndWraps() {
        var plan = makePlan()
        let ids = plan.cases.flatMap(\.steps).map(\.id)
        let navigator = StepNavigator(plan: plan)

        #expect(navigator.nextPending(after: ids[0], in: plan) == ids[1])

        plan.cases[0].steps[1].status = .passed
        #expect(navigator.nextPending(after: ids[0], in: plan) == ids[2])

        // Judging out of order: finishing the last step wraps back to the earlier unjudged one.
        plan.cases[1].steps[0].status = .failed
        #expect(plan.step(withID: ids[0])?.status == .pending)
        #expect(navigator.nextPending(after: ids[2], in: plan) == ids[0])
    }

    @Test func jumpsToTheNearestPendingStepInEitherDirection() {
        var plan = makePlan()
        let ids = plan.cases.flatMap(\.steps).map(\.id)
        let navigator = StepNavigator(plan: plan)
        judge(ids[1], .passed, in: &plan)

        // Pending: a1 (ids[0]) and b1 (ids[2]). a2 is judged.
        #expect(navigator.pendingStep(from: ids[0], forward: true, in: plan) == ids[2])
        #expect(navigator.pendingStep(from: ids[1], forward: true, in: plan) == ids[2])
        #expect(navigator.pendingStep(from: ids[2], forward: false, in: plan) == ids[0])
        #expect(navigator.pendingStep(from: ids[1], forward: false, in: plan) == ids[0])
    }

    @Test func jumpingWrapsAndLandsOnTheOnlyPendingStep() {
        var plan = makePlan()
        let ids = plan.cases.flatMap(\.steps).map(\.id)
        let navigator = StepNavigator(plan: plan)

        #expect(navigator.pendingStep(from: ids[2], forward: true, in: plan) == ids[0])
        #expect(navigator.pendingStep(from: ids[0], forward: false, in: plan) == ids[2])

        judge(ids[0], .passed, in: &plan)
        judge(ids[1], .failed, in: &plan)
        #expect(navigator.pendingStep(from: ids[2], forward: true, in: plan) == ids[2])
        #expect(navigator.pendingStep(from: ids[2], forward: false, in: plan) == ids[2])
    }

    @Test func jumpingWithoutAReferenceStartsAtTheEnds() {
        let plan = makePlan()
        let ids = plan.cases.flatMap(\.steps).map(\.id)
        let navigator = StepNavigator(plan: plan)

        #expect(navigator.pendingStep(from: nil, forward: true, in: plan) == ids[0])
        #expect(navigator.pendingStep(from: nil, forward: false, in: plan) == ids[2])
        #expect(navigator.pendingStep(from: "st_unknown", forward: true, in: plan) == ids[0])
    }

    @Test func jumpingFindsNothingWhenEveryStepHasAVerdict() {
        var plan = makePlan()
        let ids = plan.cases.flatMap(\.steps).map(\.id)
        let navigator = StepNavigator(plan: plan)
        for id in ids { judge(id, .passed, in: &plan) }

        #expect(navigator.pendingStep(from: ids[0], forward: true, in: plan) == nil)
        #expect(navigator.pendingStep(from: nil, forward: false, in: plan) == nil)
    }

    @Test func reportsNoPendingStepsWhenEverythingIsJudged() {
        var plan = makePlan()
        let ids = plan.cases.flatMap(\.steps).map(\.id)
        for caseIndex in plan.cases.indices {
            for stepIndex in plan.cases[caseIndex].steps.indices {
                plan.cases[caseIndex].steps[stepIndex].status = .passed
            }
        }
        let navigator = StepNavigator(plan: plan)
        #expect(navigator.nextPending(after: ids[0], in: plan) == nil)
        #expect(navigator.nextPending(after: "st_unknown", in: plan) == nil)
    }

    @Test(arguments: [("p", StepStatus.passed), ("P", .passed), ("f", .failed), ("F", .failed), ("b", .blocked), ("B", .blocked)])
    func mapsLettersToVerdicts(character: String, expected: StepStatus) {
        #expect(StatusKey.status(for: character) == expected)
    }

    @Test(arguments: ["", "x", "1", " ", "pp", "\u{1B}"])
    func ignoresOtherKeys(character: String) {
        #expect(StatusKey.status(for: character) == nil)
    }
}

/// Records announcements instead of talking to the system notification center.
@MainActor
final class RecordingNotifier: PlanNotifying {
    var onOpenPlan: ((String) -> Void)?
    private(set) var announced: [TestPlan] = []

    func planCreated(_ plan: TestPlan) async {
        announced.append(plan)
    }
}

@MainActor
struct PlanNotificationTests {
    private func makeModel(notifier: RecordingNotifier?) -> AppModel {
        let suite = "ManualTestPlanTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PlanStore(persistence: PlanPersistence(rootDirectory: URL.temporaryDirectory.appending(path: UUID().uuidString)))
        return AppModel(store: store, defaults: defaults, notifier: notifier)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func announcesEachPlanAnAgentCreates() async {
        let notifier = RecordingNotifier()
        let model = makeModel(notifier: notifier)

        let first = model.store.createPlan(title: "One", agentName: "Claude Code", cases: [TestCase(title: "C", steps: [TestStep(instruction: "x")])])
        let second = model.store.createPlan(title: "Two", cases: [TestCase(title: "C", steps: [TestStep(instruction: "x")])])
        await settle()

        #expect(notifier.announced.map(\.id) == [first.id, second.id])
        #expect(notifier.announced.first?.agentName == "Claude Code")
    }

    @Test func clickingANotificationOpensThatPlansWindow() {
        let notifier = RecordingNotifier()
        let model = makeModel(notifier: notifier)
        let plan = model.store.createPlan(title: "One", cases: [TestCase(title: "C", steps: [TestStep(instruction: "x")])])
        model.store.consumeWindowRequest(plan.id)
        #expect(model.store.windowRequests.isEmpty)

        notifier.onOpenPlan?(plan.id)

        #expect(model.store.windowRequests == [plan.id])
    }

    @Test func clickingAStaleNotificationDoesNothing() {
        let notifier = RecordingNotifier()
        let model = makeModel(notifier: notifier)

        notifier.onOpenPlan?("tp_gone")

        #expect(model.store.windowRequests.isEmpty)
    }

    @Test func worksWithoutANotifier() {
        let model = makeModel(notifier: nil)
        model.store.createPlan(title: "Quiet", cases: [TestCase(title: "C", steps: [TestStep(instruction: "x")])])
        #expect(model.store.plans.count == 1)
    }
}

//
//  PlanStore.swift
//  ManualTestPlan
//

import Foundation
import Observation
import OSLog

/// The single source of truth for active test plans.
///
/// SwiftUI views read ``plans`` and call the user-facing mutators (`setStatus`, `setNote`, evidence).
/// The MCP tool handlers call the agent-facing operations (`createPlan`, `appendCases`, `complete`, …).
/// Every mutation is applied in memory first and then persisted by a debounced, per-plan serialized save.
///
/// Call ``load()`` and wait for it to finish before accepting agent requests, so freshly created plans
/// can't be overwritten by the initial disk read.
@MainActor
@Observable
final class PlanStore {
    /// All active plans, oldest first.
    private(set) var plans: [TestPlan] = []

    /// Whether ``load()`` has finished.
    private(set) var isLoaded = false

    /// IDs of plans whose windows should be opened, in request order. The UI removes IDs with
    /// ``consumeWindowRequest(_:)`` once it has acted on them.
    private(set) var windowRequests: [String] = []

    /// Called after an agent creates a plan, once it is in ``plans``. The app uses it to notify the user.
    @ObservationIgnored var onPlanCreated: ((TestPlan) -> Void)?

    @ObservationIgnored private let persistence: PlanPersistence
    @ObservationIgnored private let logger = Logger(subsystem: "com.joshuasullivan.ManualTestPlan", category: "Store")
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var completing: Set<String> = []
    @ObservationIgnored private var userRevisions: [String: Int] = [:]
    @ObservationIgnored private var waiters: [UUID: Waiter] = [:]

    private struct Waiter {
        let planID: String
        let continuation: CheckedContinuation<Void, Never>
    }

    /// Creates a store.
    /// - Parameter persistence: Where plans are saved. Tests pass one rooted in a temporary directory.
    init(persistence: PlanPersistence = PlanPersistence()) {
        self.persistence = persistence
    }

    // MARK: - Loading

    /// Reads saved plans from disk and sweeps orphaned files.
    func load() async {
        let loaded = await persistence.loadAll()
        await persistence.sweepOrphans(knownPlans: loaded)
        plans = loaded
        isLoaded = true
    }

    /// Waits for every scheduled save to reach disk. Used at termination and in tests.
    func flushPendingSaves() async {
        for task in Array(saveTasks.values) {
            await task.value
        }
    }

    // MARK: - Queries

    /// The active plan with the given ID.
    /// - Parameter id: The plan's ID.
    func plan(id: String) -> TestPlan? {
        plans.first { $0.id == id }
    }

    /// Plans matching a keyword query.
    ///
    /// The query is split on whitespace and every term must match somewhere in the plan (see
    /// ``TestPlan/matches(_:)``). A nil or blank query returns every plan.
    /// - Parameter query: Keywords to look for.
    func search(matching query: String?) -> [TestPlan] {
        let terms = (query ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return plans }
        return plans.filter { plan in terms.allSatisfy(plan.matches) }
    }

    /// Reads an evidence file's bytes from disk.
    /// - Parameters:
    ///   - file: The reference stored on a step.
    ///   - planID: The owning plan.
    func evidenceData(for file: EvidenceFile, inPlan planID: String) async throws -> Data {
        try await persistence.readEvidence(filename: file.storedFilename, planID: planID)
    }

    /// Where an evidence file is stored on disk, or nil if the identifiers are invalid.
    /// - Parameters:
    ///   - file: The reference stored on a step.
    ///   - planID: The owning plan.
    func evidenceURL(for file: EvidenceFile, inPlan planID: String) -> URL? {
        try? persistence.evidenceFileURL(filename: file.storedFilename, planID: planID)
    }

    // MARK: - Agent operations

    /// Creates and persists a new plan, and asks the UI to open its window.
    /// - Parameters:
    ///   - title: Short title.
    ///   - summary: What is being tested and why.
    ///   - context: Optional project/build details.
    ///   - agentName: The creating MCP client's name.
    ///   - cases: The test cases.
    /// - Returns: The stored plan, including its generated IDs.
    @discardableResult
    func createPlan(
        title: String,
        summary: String = "",
        context: String = "",
        agentName: String? = nil,
        cases: [TestCase]
    ) -> TestPlan {
        var plan = TestPlan(title: title, summary: summary, context: context, agentName: agentName, cases: cases)
        while plans.contains(where: { $0.id == plan.id }) {
            plan.id = ShortID.make(prefix: "tp")
        }
        plans.append(plan)
        scheduleSave(plan.id)
        windowRequests.append(plan.id)
        onPlanCreated?(plan)
        return plan
    }

    /// Appends test cases to the end of a plan.
    /// - Parameters:
    ///   - cases: The cases to add.
    ///   - planID: The plan to extend.
    func appendCases(_ cases: [TestCase], toPlan planID: String) throws {
        try mutate(planID) { $0.cases.append(contentsOf: cases) }
    }

    /// Appends steps to the end of an existing case.
    /// - Parameters:
    ///   - steps: The steps to add.
    ///   - caseID: The case to extend.
    ///   - planID: The plan containing the case.
    func appendSteps(_ steps: [TestStep], toCase caseID: String, inPlan planID: String) throws {
        try mutate(planID) { plan in
            guard let index = plan.cases.firstIndex(where: { $0.id == caseID }) else {
                throw PlanStoreError.caseNotFound(caseID)
            }
            plan.cases[index].steps.append(contentsOf: steps)
        }
    }

    /// Rewrites a step's instruction and/or expected result and returns it to `pending`.
    ///
    /// The user's note and evidence are kept so earlier observations aren't lost.
    /// - Parameters:
    ///   - stepID: The step to revise.
    ///   - planID: The plan containing the step.
    ///   - instruction: New instruction, or nil to keep the current one.
    ///   - expected: New expected result, or nil to keep the current one.
    func reviseStep(_ stepID: String, inPlan planID: String, instruction: String?, expected: String?) throws {
        try mutateStep(stepID, inPlan: planID) { step in
            if let instruction { step.instruction = instruction }
            if let expected { step.expected = expected }
            step.status = .pending
        }
    }

    /// Finishes a plan: deletes its directory (including all evidence) and removes it from memory.
    ///
    /// The plan is only removed after the files are gone, so a failure leaves it intact and is reported.
    /// - Parameters:
    ///   - planID: The plan to complete.
    ///   - force: Complete even if some steps have no verdict. Without it, pending steps cause an error.
    /// - Returns: The plan as it was at completion, for the agent's final report.
    func complete(planID: String, force: Bool) async throws -> TestPlan {
        guard plan(id: planID) != nil else { throw PlanStoreError.planNotFound(planID) }
        guard completing.insert(planID).inserted else { throw PlanStoreError.planIsBeingCompleted(planID) }
        defer { completing.remove(planID) }

        if !force, let plan = plan(id: planID) {
            let unresolved = plan.cases.flatMap(\.steps).filter { $0.status == .pending }.map(\.id)
            if !unresolved.isEmpty {
                throw PlanStoreError.unresolvedSteps(unresolved)
            }
        }

        // Let any in-flight save land, then stop new ones, so nothing recreates the directory afterwards.
        let pending = saveTasks.removeValue(forKey: planID)
        pending?.cancel()
        await pending?.value

        guard let snapshot = plan(id: planID) else { throw PlanStoreError.planNotFound(planID) }
        try await persistence.delete(planID: planID)

        plans.removeAll { $0.id == planID }
        windowRequests.removeAll { $0 == planID }
        userRevisions.removeValue(forKey: planID)
        wakeWaiters(for: planID)
        return snapshot
    }

    // MARK: - User operations

    /// Records the user's verdict on a step.
    /// - Parameters:
    ///   - status: The new status.
    ///   - stepID: The step being judged.
    ///   - planID: The plan containing the step.
    func setStatus(_ status: StepStatus, forStep stepID: String, inPlan planID: String) throws {
        try mutateStep(stepID, inPlan: planID, wakesWaiters: true) { $0.status = status }
    }

    /// Replaces a step's note. Saves are debounced because this is called on every keystroke.
    /// - Parameters:
    ///   - note: The full note text.
    ///   - stepID: The step being annotated.
    ///   - planID: The plan containing the step.
    func setNote(_ note: String, forStep stepID: String, inPlan planID: String) throws {
        try mutateStep(stepID, inPlan: planID, debounce: .milliseconds(300)) { $0.note = note }
    }

    /// Attaches a file of any type to a step as evidence.
    ///
    /// The file is written before the reference is added, so a saved plan never points at a missing file.
    /// - Parameters:
    ///   - data: The file's contents. Images are expected to be normalized by the caller.
    ///   - name: The file name to show, such as `crash.log`.
    ///   - stepID: The step to attach it to.
    ///   - planID: The plan containing the step.
    /// - Returns: The stored record.
    /// - Throws: ``PlanStoreError/evidenceTooLarge(name:limit:)`` above ``EvidenceFile/maxByteCount``.
    @discardableResult
    func addEvidence(_ data: Data, named name: String, toStep stepID: String, inPlan planID: String) async throws -> EvidenceFile {
        guard let plan = plan(id: planID) else { throw PlanStoreError.planNotFound(planID) }
        guard plan.step(withID: stepID) != nil else { throw PlanStoreError.stepNotFound(stepID) }
        guard !completing.contains(planID) else { throw PlanStoreError.planIsBeingCompleted(planID) }
        guard data.count <= EvidenceFile.maxByteCount else {
            throw PlanStoreError.evidenceTooLarge(name: name, limit: EvidenceFile.maxByteCount)
        }

        let file = EvidenceFile(name: name, byteCount: data.count)
        try await persistence.writeEvidence(data, filename: file.storedFilename, planID: planID)
        do {
            try mutateStep(stepID, inPlan: planID, wakesWaiters: true) { $0.evidence.append(file) }
        } catch {
            try? await persistence.deleteEvidence(filename: file.storedFilename, planID: planID)
            throw error
        }
        return file
    }

    /// Removes an evidence file: the reference first, then the file once the updated plan is saved.
    /// - Parameters:
    ///   - fileID: The ``EvidenceFile/id`` to remove.
    ///   - stepID: The step it's attached to.
    ///   - planID: The plan containing the step.
    func removeEvidence(_ fileID: String, fromStep stepID: String, inPlan planID: String) async throws {
        var removed: EvidenceFile?
        try mutateStep(stepID, inPlan: planID) { step in
            removed = step.evidence.first { $0.id == fileID }
            step.evidence.removeAll { $0.id == fileID }
        }
        guard let removed else { return }
        await saveTasks[planID]?.value
        try await persistence.deleteEvidence(filename: removed.storedFilename, planID: planID)
    }

    /// Acknowledges a window request so it isn't acted on twice.
    /// - Parameter planID: The plan whose window was opened.
    func consumeWindowRequest(_ planID: String) {
        windowRequests.removeAll { $0 == planID }
    }

    /// Asks the UI to open (or focus) a plan's window, such as from the menu bar list.
    /// - Parameter planID: The plan to show.
    func requestWindow(for planID: String) {
        guard plan(id: planID) != nil, !windowRequests.contains(planID) else { return }
        windowRequests.append(planID)
    }

    // MARK: - Waiting for the user

    /// A counter that increases whenever the user records a verdict or attaches evidence in a plan.
    ///
    /// Notes don't count, because they change on every keystroke. Agents pass the value they last saw to
    /// ``waitForUserChange(planID:since:timeout:)``.
    /// - Parameter planID: The plan to check.
    func userRevision(of planID: String) -> Int {
        userRevisions[planID, default: 0]
    }

    /// Suspends until the user changes the plan past `revision`, the plan is completed, or the timeout passes.
    ///
    /// Returns immediately if the revision has already moved on or the plan doesn't exist.
    /// - Parameters:
    ///   - planID: The plan to watch.
    ///   - revision: The last revision the caller saw.
    ///   - timeout: The longest to wait.
    func waitForUserChange(planID: String, since revision: Int, timeout: Duration) async {
        guard plan(id: planID) != nil, userRevision(of: planID) <= revision else { return }
        let waiterID = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters[waiterID] = Waiter(planID: planID, continuation: continuation)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.waiters.removeValue(forKey: waiterID)?.continuation.resume()
            }
        }
    }

    private func wakeWaiters(for planID: String) {
        for (id, waiter) in waiters where waiter.planID == planID {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    // MARK: - Mutation plumbing

    /// Applies `body` to a copy of the plan and commits it only if `body` doesn't throw.
    private func mutate(
        _ planID: String,
        debounce: Duration = .zero,
        wakesWaiters: Bool = false,
        _ body: (inout TestPlan) throws -> Void
    ) throws {
        guard !completing.contains(planID) else { throw PlanStoreError.planIsBeingCompleted(planID) }
        guard let index = plans.firstIndex(where: { $0.id == planID }) else {
            throw PlanStoreError.planNotFound(planID)
        }
        var plan = plans[index]
        try body(&plan)
        plan.updatedAt = .now
        plans[index] = plan
        scheduleSave(planID, debounce: debounce)
        if wakesWaiters {
            userRevisions[planID, default: 0] += 1
            wakeWaiters(for: planID)
        }
    }

    private func mutateStep(
        _ stepID: String,
        inPlan planID: String,
        debounce: Duration = .zero,
        wakesWaiters: Bool = false,
        _ body: (inout TestStep) -> Void
    ) throws {
        try mutate(planID, debounce: debounce, wakesWaiters: wakesWaiters) { plan in
            guard let location = plan.location(ofStep: stepID) else { throw PlanStoreError.stepNotFound(stepID) }
            body(&plan.cases[location.caseIndex].steps[location.stepIndex])
            plan.cases[location.caseIndex].steps[location.stepIndex].updatedAt = .now
        }
    }

    /// Schedules a save of the plan's latest state. Saves for one plan run one at a time, in order, and a
    /// newer request replaces an older one that hasn't started writing.
    private func scheduleSave(_ planID: String, debounce: Duration = .zero) {
        let previous = saveTasks[planID]
        previous?.cancel()
        saveTasks[planID] = Task { [weak self] in
            await previous?.value
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            await self?.writePlan(planID)
        }
    }

    private func writePlan(_ planID: String) async {
        guard !completing.contains(planID), let plan = plan(id: planID) else { return }
        do {
            try await persistence.save(plan)
        } catch {
            logger.error("Failed to save \(planID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

//
//  PlanTools.swift
//  ManualTestPlan
//

import Foundation

/// Implements the MCP tools on top of ``PlanStore``.
@MainActor
final class PlanTools: MCPToolProvider {
    private let store: PlanStore

    /// Longest `wait_for_test_plan` is allowed to block, keeping it under typical client request timeouts.
    private static let maxWaitSeconds = 60
    private static let defaultWaitSeconds = 30

    /// Creates the tool set.
    /// - Parameter store: The store the tools read and mutate.
    init(store: PlanStore) {
        self.store = store
    }

    var instructions: String { PlanToolSchemas.instructions }
    var definitions: [MCPToolDefinition] { PlanToolSchemas.all }

    func call(name: String, arguments: JSONValue, context: MCPCallContext) async -> MCPToolResult {
        do {
            switch name {
            case "create_test_plan": return try createPlan(arguments, context: context)
            case "get_test_plan": return try getPlan(arguments)
            case "wait_for_test_plan": return try await waitForPlan(arguments)
            case "get_step_evidence": return try await getEvidence(arguments)
            case "list_test_plans": return try listPlans(arguments)
            case "add_to_test_plan": return try addToPlan(arguments)
            case "revise_step": return try reviseStep(arguments)
            case "complete_test_plan": return try await completePlan(arguments)
            default: return .error("Unknown tool: \(name)")
            }
        } catch let error as DecodingError {
            return .error("Invalid arguments: \(Self.describe(error))")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Argument types

    private struct StepArguments: Decodable {
        var instruction: String
        var expected: String?
    }

    private struct CaseArguments: Decodable {
        var title: String
        var preconditions: String?
        var steps: [StepArguments]
    }

    private struct CreateArguments: Decodable {
        var title: String
        var summary: String?
        var context: String?
        var cases: [CaseArguments]
    }

    private struct PlanArguments: Decodable {
        var planId: String
        var detail: String?
    }

    private struct WaitArguments: Decodable {
        var planId: String
        var sinceRevision: Int?
        var timeoutSeconds: Int?
    }

    private struct StepReference: Decodable {
        var planId: String
        var stepId: String
    }

    private struct ListArguments: Decodable {
        var query: String?
    }

    private struct AddArguments: Decodable {
        var planId: String
        var cases: [CaseArguments]?
        var caseId: String?
        var steps: [StepArguments]?
    }

    private struct ReviseArguments: Decodable {
        var planId: String
        var stepId: String
        var instruction: String?
        var expected: String?
    }

    private struct CompleteArguments: Decodable {
        var planId: String
        var force: Bool?
    }

    // MARK: - Tools

    private func createPlan(_ arguments: JSONValue, context: MCPCallContext) throws -> MCPToolResult {
        let input = try arguments.decoded(as: CreateArguments.self)
        let title = try Self.required(input.title, field: "title")
        guard !input.cases.isEmpty else { throw ToolInputError("'cases' must contain at least one test case.") }

        let plan = store.createPlan(
            title: title,
            summary: Self.trimmed(input.summary),
            context: Self.trimmed(input.context),
            agentName: context.clientName,
            cases: try input.cases.map(Self.makeCase)
        )
        return .json(CreatedOutput(
            planID: plan.id,
            message: "Plan created and opened on the user's Mac. Tell the user it is waiting, then call wait_for_test_plan.",
            cases: plan.cases
        ))
    }

    private func getPlan(_ arguments: JSONValue) throws -> MCPToolResult {
        let input = try arguments.decoded(as: PlanArguments.self)
        let plan = try requirePlan(input.planId)
        let detail: CaseOutput.Detail = input.detail == "full" ? .full : .summary
        return .json(PlanOutput(plan, revision: store.userRevision(of: plan.id), detail: detail))
    }

    private func waitForPlan(_ arguments: JSONValue) async throws -> MCPToolResult {
        let input = try arguments.decoded(as: WaitArguments.self)
        let planID = try requirePlan(input.planId).id
        let seconds = min(max(input.timeoutSeconds ?? Self.defaultWaitSeconds, 1), Self.maxWaitSeconds)
        let since = input.sinceRevision ?? store.userRevision(of: planID)

        await store.waitForUserChange(planID: planID, since: since, timeout: .seconds(seconds))

        let plan = try requirePlan(planID)
        let revision = store.userRevision(of: planID)
        let changed = revision > since
        let hint = if plan.isResolved {
            "Every step has a verdict. Review failed and blocked steps, then call complete_test_plan when you're done."
        } else if changed {
            "The user is making progress. Call wait_for_test_plan again with since_revision=\(revision)."
        } else {
            "No change yet. Call wait_for_test_plan again with since_revision=\(revision)."
        }
        return .json(WaitOutput(
            changed: changed,
            timedOut: !changed,
            hint: hint,
            plan: PlanOutput(plan, revision: revision, detail: .summary)
        ))
    }

    private func getEvidence(_ arguments: JSONValue) async throws -> MCPToolResult {
        let input = try arguments.decoded(as: StepReference.self)
        let plan = try requirePlan(input.planId)
        guard let step = plan.step(withID: input.stepId) else { throw PlanStoreError.stepNotFound(input.stepId) }

        var result = MCPToolResult.json(StepOutput(step))
        for image in step.evidence {
            do {
                let data = try await store.evidenceData(for: image, inPlan: plan.id)
                result.content.append(.image(data, mimeType: "image/png"))
            } catch {
                result.content.append(.text("Screenshot \(image.id) could not be read: \(error.localizedDescription)"))
            }
        }
        return result
    }

    private func listPlans(_ arguments: JSONValue) throws -> MCPToolResult {
        let input = try arguments.decoded(as: ListArguments.self)
        return .json(store.search(matching: input.query).map(PlanListItem.init))
    }

    private func addToPlan(_ arguments: JSONValue) throws -> MCPToolResult {
        let input = try arguments.decoded(as: AddArguments.self)
        let planID = try requirePlan(input.planId).id
        let newCases = input.cases ?? []
        let newSteps = input.steps ?? []

        switch (newCases.isEmpty, input.caseId, newSteps.isEmpty) {
        case (false, nil, true):
            let cases = try newCases.map(Self.makeCase)
            try store.appendCases(cases, toPlan: planID)
            return .json(CreatedOutput(planID: planID, message: "Added \(cases.count) case(s).", cases: cases))
        case (true, let caseID?, false):
            let steps = try newSteps.map(Self.makeStep)
            try store.appendSteps(steps, toCase: caseID, inPlan: planID)
            return .json(CreatedOutput(planID: planID, message: "Added \(steps.count) step(s).", steps: steps))
        default:
            throw ToolInputError("Provide either 'cases', or both 'case_id' and 'steps' — not a mix, and not neither.")
        }
    }

    private func reviseStep(_ arguments: JSONValue) throws -> MCPToolResult {
        let input = try arguments.decoded(as: ReviseArguments.self)
        let planID = try requirePlan(input.planId).id
        let instruction = try input.instruction.map { try Self.required($0, field: "instruction") }
        let expected = input.expected.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard instruction != nil || expected != nil else {
            throw ToolInputError("Provide 'instruction', 'expected', or both.")
        }

        try store.reviseStep(input.stepId, inPlan: planID, instruction: instruction, expected: expected)
        guard let step = store.plan(id: planID)?.step(withID: input.stepId) else {
            throw PlanStoreError.stepNotFound(input.stepId)
        }
        return .json(StepOutput(step))
    }

    private func completePlan(_ arguments: JSONValue) async throws -> MCPToolResult {
        let input = try arguments.decoded(as: CompleteArguments.self)
        let plan = try await store.complete(planID: input.planId, force: input.force ?? false)
        let header = "Test plan \(plan.id) was completed and deleted from the user's Mac, including its screenshots. Final report:\n\n"
        return .text(header + PlanReport.markdown(for: plan, includeIDs: true))
    }

    // MARK: - Helpers

    private func requirePlan(_ id: String) throws -> TestPlan {
        guard let plan = store.plan(id: id) else { throw PlanStoreError.planNotFound(id) }
        return plan
    }

    private static func trimmed(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func required(_ text: String, field: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ToolInputError("'\(field)' must not be empty.") }
        return value
    }

    private static func makeStep(_ input: StepArguments) throws -> TestStep {
        TestStep(instruction: try required(input.instruction, field: "instruction"), expected: trimmed(input.expected))
    }

    private static func makeCase(_ input: CaseArguments) throws -> TestCase {
        let title = try required(input.title, field: "title")
        guard !input.steps.isEmpty else { throw ToolInputError("Case '\(title)' must contain at least one step.") }
        return TestCase(title: title, preconditions: trimmed(input.preconditions), steps: try input.steps.map(makeStep))
    }

    /// Turns a decoding failure into a sentence an agent can act on.
    private static func describe(_ error: DecodingError) -> String {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingPrefix(".").description
        }
        switch error {
        case .keyNotFound(let key, let context):
            let location = path(context.codingPath)
            return "missing required field '\(location.isEmpty ? key.stringValue : "\(location).\(key.stringValue)")'."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "field '\(path(context.codingPath))' has the wrong type or is null."
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// A problem with the arguments an agent passed, reported back verbatim.
private struct ToolInputError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

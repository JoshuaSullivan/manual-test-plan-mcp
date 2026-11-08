//
//  StepNavigator.swift
//  ManualTestPlan
//

import Foundation

/// Keyboard navigation over a plan's steps in display order, across case boundaries.
nonisolated struct StepNavigator: Equatable {
    /// Every step ID in the plan, in the order the user sees them.
    let order: [String]

    /// Creates a navigator for a plan.
    /// - Parameter plan: The plan whose steps to walk.
    init(plan: TestPlan) {
        order = plan.cases.flatMap(\.steps).map(\.id)
    }

    /// The step after `stepID`, or nil at the end.
    func next(after stepID: String) -> String? {
        guard let index = order.firstIndex(of: stepID), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    /// The step before `stepID`, or nil at the start.
    func previous(before stepID: String) -> String? {
        guard let index = order.firstIndex(of: stepID), index > 0 else { return nil }
        return order[index - 1]
    }

    /// The step to focus when the user finishes `stepID`: the next one that still has no verdict, searching
    /// forward and then wrapping, so marking steps in a different order never strands the user.
    /// - Parameters:
    ///   - stepID: The step just judged.
    ///   - plan: The plan, for current statuses.
    /// - Returns: The next pending step, or nil when none remain.
    func nextPending(after stepID: String, in plan: TestPlan) -> String? {
        guard let index = order.firstIndex(of: stepID) else { return nil }
        let rotated = order[(index + 1)...] + order[..<index]
        return rotated.first { plan.step(withID: $0)?.status == .pending }
    }

    /// The nearest step without a verdict in one direction, wrapping around the ends. This backs the floating
    /// previous/next buttons.
    ///
    /// Unlike ``nextPending(after:in:)``, the reference step itself is a candidate once the search has gone
    /// all the way round, so the buttons still land somewhere when it is the only unjudged step left.
    /// - Parameters:
    ///   - reference: The step the user is working on. When nil or unknown, searching forward returns the
    ///     first pending step and searching backward returns the last.
    ///   - forward: `true` to search toward the end of the plan, `false` toward the start.
    ///   - plan: The plan, for current statuses.
    /// - Returns: The step to go to, or nil when every step has a verdict.
    func pendingStep(from reference: String?, forward: Bool, in plan: TestPlan) -> String? {
        let isPending = { (id: String) in plan.step(withID: id)?.status == .pending }
        guard let reference, let index = order.firstIndex(of: reference) else {
            return forward ? order.first(where: isPending) : order.last(where: isPending)
        }
        if forward {
            return (order[(index + 1)...] + order[...index]).first(where: isPending)
        } else {
            return (order[..<index].reversed() + order[index...].reversed()).first(where: isPending)
        }
    }
}

/// The verdict a key press maps to.
nonisolated enum StatusKey {
    /// The status for a typed character, case-insensitively: `p` passed, `f` failed, `b` blocked.
    /// - Parameter character: What the user typed.
    static func status(for character: String) -> StepStatus? {
        switch character.lowercased() {
        case "p": .passed
        case "f": .failed
        case "b": .blocked
        default: nil
        }
    }
}

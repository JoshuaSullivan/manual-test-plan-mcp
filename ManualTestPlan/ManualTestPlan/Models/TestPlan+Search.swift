//
//  TestPlan+Search.swift
//  ManualTestPlan
//

import Foundation

extension TestPlan {
    /// Whether a single search term appears anywhere in the plan's text.
    ///
    /// Searches the ID, title, summary, context, agent name, case titles and preconditions, and every step's
    /// instruction, expected result, and note, using locale-aware, case- and diacritic-insensitive matching.
    /// - Parameter term: One word or phrase.
    func matches(_ term: String) -> Bool {
        var fields = [id, title, summary, context, agentName ?? ""]
        for testCase in cases {
            fields.append(testCase.title)
            fields.append(testCase.preconditions)
            for step in testCase.steps {
                fields.append(step.instruction)
                fields.append(step.expected)
                fields.append(step.note)
            }
        }
        return fields.contains { $0.localizedStandardContains(term) }
    }
}

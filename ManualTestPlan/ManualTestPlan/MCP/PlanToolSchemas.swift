//
//  PlanToolSchemas.swift
//  ManualTestPlan
//

import Foundation

/// Tool names, descriptions, and JSON Schemas as advertised to agents.
///
/// The descriptions are the agent's only documentation, so they spell out the workflow and the meaning of
/// each status rather than just naming the parameters.
nonisolated enum PlanToolSchemas {
    /// Guidance returned from `initialize`.
    static let instructions = """
        ManualTestPlan hands a checklist of manual checks to the human user and returns their verdicts. \
        Use it for things you cannot verify yourself: gestures, drag and drop, visual polish, animations, \
        permission prompts, hardware, or anything the accessibility tree does not expose.

        Workflow:
        1. create_test_plan with small, concrete, ordered steps. Give each step one observable outcome and \
        put it in `expected`. A window opens for the user automatically; tell them it is waiting.
        2. Call wait_for_test_plan repeatedly, passing back the `revision` it returns as `since_revision`, \
        until `resolved` is true. Or do other work and poll with get_test_plan.
        3. Read the user's notes on failed and blocked steps, and call get_step_evidence to see any \
        screenshots, logs, or other files they attached (steps report `evidence_count`).
        4. A `blocked` step means the user could not perform or verify it, usually because your instructions \
        did not match what is on screen. Fix the instructions with revise_step instead of treating it as an \
        app bug. A `failed` step means the step ran and the behavior was wrong.
        5. When you are done, call complete_test_plan. That deletes the plan and all attached files, so fetch any \
        evidence you need first.
        """

    /// Every tool, in the order they're advertised.
    static let all: [MCPToolDefinition] = [
        createTestPlan, getTestPlan, waitForTestPlan, getStepEvidence,
        listTestPlans, addToTestPlan, reviseStep, completeTestPlan
    ]

    // MARK: - Tools

    static let createTestPlan = MCPToolDefinition(
        name: "create_test_plan",
        description: """
            Create a manual test plan for the user to work through and open it in a window on their Mac. \
            Returns the plan_id plus case_id and step_id values; keep them to query results later. \
            Write each step as an action the user can perform plus the outcome they should see. The user marks \
            every step passed, failed, or blocked, and may add notes and attach files such as screenshots or logs.
            """,
        inputSchema: object(
            properties: [
                "title": string("Short title for the plan, e.g. 'Kanban drag and drop'."),
                "summary": string("What is being tested and why. Optional."),
                "context": string("Project, branch, build, or setup the user should know about. Optional."),
                "cases": ["type": "array", "minItems": 1, "items": caseSchema,
                          "description": "Groups of steps, each verifying one behavior."]
            ],
            required: ["title", "cases"]
        )
    )

    static let getTestPlan = MCPToolDefinition(
        name: "get_test_plan",
        description: """
            Get the current status and results of a plan. detail='summary' (default) returns counts plus only \
            the failed and blocked steps with the user's notes; detail='full' returns every step. The returned \
            `revision` can be passed to wait_for_test_plan.
            """,
        inputSchema: object(
            properties: [
                "plan_id": string("The plan_id from create_test_plan."),
                "detail": ["type": "string", "enum": ["summary", "full"], "description": "How many steps to include. Defaults to 'summary'."]
            ],
            required: ["plan_id"]
        )
    )

    static let waitForTestPlan = MCPToolDefinition(
        name: "wait_for_test_plan",
        description: """
            Block until the user records a verdict or attaches a file after `since_revision`, or until \
            the timeout passes. Typing a note does not wake it. Returns the plan summary, `changed`, and \
            `timed_out`. Keep calling it, passing the returned `revision` as `since_revision`, until \
            `resolved` is true. If since_revision is omitted, the wait starts from the current revision.
            """,
        inputSchema: object(
            properties: [
                "plan_id": string("The plan_id from create_test_plan."),
                "since_revision": ["type": "integer", "minimum": 0, "description": "The `revision` from your last get_test_plan or wait_for_test_plan call."],
                "timeout_seconds": ["type": "integer", "minimum": 1, "maximum": 60, "description": "How long to wait. Defaults to 30; capped at 60."]
            ],
            required: ["plan_id"]
        )
    )

    static let getStepEvidence = MCPToolDefinition(
        name: "get_step_evidence",
        description: """
            Get the files and note the user attached to one step as evidence: screenshots, logs, crash reports, \
            or anything else. Images are returned as image content and text files inline (very long ones keep \
            their beginning and end). Other files are described, and every file's `local_path` lets you open the \
            full file yourself.
            """,
        inputSchema: object(
            properties: [
                "plan_id": string("The plan_id from create_test_plan."),
                "step_id": string("A step_id from get_test_plan.")
            ],
            required: ["plan_id", "step_id"]
        )
    )

    static let listTestPlans = MCPToolDefinition(
        name: "list_test_plans",
        description: """
            List active test plans, optionally filtered by keywords. Every word must appear somewhere in the \
            plan (ID, title, summary, context, case titles, step text, or the user's notes). Use this to \
            recover a plan_id after losing it, for example after your context was reset.
            """,
        inputSchema: object(
            properties: ["query": string("Keywords to search for. Omit to list every active plan.")],
            required: []
        )
    )

    static let addToTestPlan = MCPToolDefinition(
        name: "add_to_test_plan",
        description: """
            Add to an existing plan without disturbing the user's progress. Provide either `cases` to append \
            whole new cases, or `case_id` plus `steps` to append steps to an existing case. Returns the new IDs.
            """,
        inputSchema: object(
            properties: [
                "plan_id": string("The plan_id from create_test_plan."),
                "cases": ["type": "array", "items": caseSchema, "description": "New cases to append to the plan."],
                "case_id": string("An existing case to append steps to."),
                "steps": ["type": "array", "items": stepSchema, "description": "Steps to append to `case_id`."]
            ],
            required: ["plan_id"]
        )
    )

    static let reviseStep = MCPToolDefinition(
        name: "revise_step",
        description: """
            Rewrite a step's instruction and/or expected result and reset it to pending so the user judges it \
            again. Use this after a step comes back blocked because your instructions were wrong or \
            ambiguous. The user's earlier note and attachments are kept.
            """,
        inputSchema: object(
            properties: [
                "plan_id": string("The plan_id from create_test_plan."),
                "step_id": string("The step to revise."),
                "instruction": string("The new instruction. Omit to keep the current one."),
                "expected": string("The new expected result. Omit to keep the current one.")
            ],
            required: ["plan_id", "step_id"]
        )
    )

    static let completeTestPlan = MCPToolDefinition(
        name: "complete_test_plan",
        description: """
            Finish a plan: returns the final report as Markdown, then permanently deletes the plan and every \
            attached file from the user's Mac and closes its window. Refused while steps are still pending unless \
            force=true. Fetch any evidence you need with get_step_evidence first.
            """,
        inputSchema: object(
            properties: [
                "plan_id": string("The plan_id from create_test_plan."),
                "force": ["type": "boolean", "description": "Delete the plan even though some steps have no verdict. Defaults to false."]
            ],
            required: ["plan_id"]
        )
    )

    // MARK: - Building blocks

    private static let stepSchema: JSONValue = object(
        properties: [
            "instruction": string("What the user should do, as a single concrete action."),
            "expected": string("What the user should see if it works. Optional but strongly recommended.")
        ],
        required: ["instruction"]
    )

    private static let caseSchema: JSONValue = object(
        properties: [
            "title": string("Short title for this group of steps."),
            "preconditions": string("Setup the user needs before the first step. Optional."),
            "steps": ["type": "array", "minItems": 1, "items": stepSchema, "description": "Steps in the order the user should perform them."]
        ],
        required: ["title", "steps"]
    )

    private static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    private static func object(properties: [String: JSONValue], required: [String]) -> JSONValue {
        [
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string))
        ]
    }
}

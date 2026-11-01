//
//  MCPHarness.swift
//  ManualTestPlanTests
//

import Foundation
@testable import ManualTestPlan

/// A real store, tool set, and router wired together over a temporary directory, driven with JSON-RPC bodies.
@MainActor
final class MCPHarness {
    let store: PlanStore
    let router: MCPRouter
    let root: URL
    private var nextID = 1

    /// A decoded tool result.
    struct ToolReply {
        var content: [JSONValue]
        var isError: Bool

        /// The first text block.
        var text: String {
            content.first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue ?? ""
        }

        /// The first text block parsed as JSON.
        var json: JSONValue {
            (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null
        }

        /// The image blocks' decoded bytes.
        var images: [Data] {
            content.filter { $0["type"]?.stringValue == "image" }
                .compactMap { $0["data"]?.stringValue.flatMap { Data(base64Encoded: $0) } }
        }
    }

    /// Runs `body` with a fresh harness and removes its storage afterwards.
    static func run(_ body: (MCPHarness) async throws -> Void) async throws {
        let root = URL.temporaryDirectory.appending(path: "ManualTestPlanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlanStore(persistence: PlanPersistence(rootDirectory: root))
        await store.load()
        try await body(MCPHarness(store: store, root: root))
    }

    private init(store: PlanStore, root: URL) {
        self.store = store
        self.root = root
        self.router = MCPRouter(tools: PlanTools(store: store))
    }

    /// Sends a JSON-RPC request and returns the raw HTTP-level response.
    func send(_ method: String, params: JSONValue = [:], sessionID: String? = nil) async -> MCPHTTPResponse {
        let id = nextID
        nextID += 1
        let message: JSONValue = ["jsonrpc": "2.0", "id": .int(id), "method": .string(method), "params": params]
        return await router.handle(body: (try? JSONEncoder().encode(message)) ?? Data(), sessionID: sessionID)
    }

    /// Sends a request and returns the decoded JSON-RPC envelope.
    func rpc(_ method: String, params: JSONValue = [:], sessionID: String? = nil) async -> JSONValue {
        let response = await send(method, params: params, sessionID: sessionID)
        return Self.decode(response.body)
    }

    /// Calls a tool and unpacks the result.
    func call(_ tool: String, _ arguments: JSONValue = [:], sessionID: String? = nil) async -> ToolReply {
        let envelope = await rpc("tools/call", params: ["name": .string(tool), "arguments": arguments], sessionID: sessionID)
        let result = envelope["result"]
        return ToolReply(
            content: result?["content"]?.arrayValue ?? [],
            isError: result?["isError"]?.boolValue ?? true
        )
    }

    /// Creates a two-case plan through the real tool and returns its decoded reply.
    @discardableResult
    func createSamplePlan(sessionID: String? = nil) async -> JSONValue {
        await call("create_test_plan", [
            "title": "Kanban board",
            "summary": "Drag and drop",
            "cases": [
                ["title": "Reorder", "preconditions": "Two cards", "steps": [
                    ["instruction": "Drag card A below card B", "expected": "A is below B"],
                    ["instruction": "Relaunch the app"]
                ]],
                ["title": "Cancel", "steps": [["instruction": "Press Escape mid-drag"]]]
            ]
        ], sessionID: sessionID).json
    }

    static func decode(_ data: Data?) -> JSONValue {
        guard let data, let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return value
    }
}

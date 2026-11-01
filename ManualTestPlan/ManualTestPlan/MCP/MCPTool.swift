//
//  MCPTool.swift
//  ManualTestPlan
//

import Foundation

/// A tool as advertised in `tools/list`.
nonisolated struct MCPToolDefinition: Sendable {
    /// Unique tool name, such as `create_test_plan`.
    var name: String
    /// What the tool does and when to use it. Written for the model that will read it.
    var description: String
    /// JSON Schema describing the `arguments` object.
    var inputSchema: JSONValue
}

/// One block of tool output.
nonisolated enum MCPContent: Sendable, Equatable {
    /// Plain text.
    case text(String)
    /// An image, delivered base64-encoded on the wire.
    case image(Data, mimeType: String)
}

/// The outcome of a `tools/call`.
nonisolated struct MCPToolResult: Sendable, Equatable {
    /// The output blocks.
    var content: [MCPContent]
    /// Whether the call failed. The model sees the content either way, so errors explain themselves.
    var isError = false

    /// A successful text result.
    static func text(_ text: String) -> MCPToolResult {
        MCPToolResult(content: [.text(text)])
    }

    /// A failed result whose text tells the model what went wrong and how to proceed.
    static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(content: [.text(message)], isError: true)
    }

    /// A successful result containing pretty-printed JSON with `snake_case` keys and ISO-8601 dates.
    static func json(_ value: some Encodable) -> MCPToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return .error("Internal error: could not encode the response.")
        }
        return .text(text)
    }
}

/// Information about the caller that tools may use.
nonisolated struct MCPCallContext: Sendable {
    /// The MCP client's self-reported name from `initialize`, if the session is known.
    var clientName: String?
}

/// Supplies the tools a router exposes.
@MainActor
protocol MCPToolProvider: Sendable {
    /// Guidance returned in the `initialize` result, telling agents how to use the tools together.
    var instructions: String { get }
    /// The tools to advertise.
    var definitions: [MCPToolDefinition] { get }
    /// Runs a tool. Failures are reported through ``MCPToolResult/isError``, not thrown.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - arguments: The `arguments` object (an empty object if the client sent none).
    ///   - context: Details about the caller.
    func call(name: String, arguments: JSONValue, context: MCPCallContext) async -> MCPToolResult
}

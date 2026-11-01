//
//  MCPRouter.swift
//  ManualTestPlan
//

import Foundation

/// What the HTTP layer should send back for one JSON-RPC POST.
nonisolated struct MCPHTTPResponse: Sendable, Equatable {
    /// HTTP status code.
    var status: Int
    /// JSON body, or nil for an empty response.
    var body: Data?
    /// Value for the `Mcp-Session-Id` response header, set only when a session was just created.
    var sessionID: String?
}

/// Transport-independent MCP server logic: parses one JSON-RPC message and produces the reply.
///
/// Implements the subset of MCP needed for tools: `initialize`, `ping`, `tools/list`, and `tools/call`.
/// Notifications are accepted and ignored. Batches and server-initiated messages are not supported.
nonisolated final class MCPRouter: Sendable {
    /// Protocol revisions this server will agree to, newest first.
    static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private let tools: any MCPToolProvider
    private let sessions: MCPSessionStore
    private let serverVersion: String

    /// Creates a router.
    /// - Parameters:
    ///   - tools: The tools to expose.
    ///   - sessions: Where session → client name mappings are kept.
    ///   - serverVersion: Reported in `serverInfo`.
    init(tools: any MCPToolProvider, sessions: MCPSessionStore = MCPSessionStore(), serverVersion: String = "1.0") {
        self.tools = tools
        self.sessions = sessions
        self.serverVersion = serverVersion
    }

    /// Ends a session on behalf of an HTTP `DELETE`.
    /// - Parameter sessionID: The `Mcp-Session-Id` header value.
    func endSession(_ sessionID: String) async {
        await sessions.endSession(sessionID)
    }

    /// Handles the body of one HTTP POST.
    /// - Parameters:
    ///   - body: The raw request body.
    ///   - sessionID: The request's `Mcp-Session-Id` header, if present.
    func handle(body: Data, sessionID: String?) async -> MCPHTTPResponse {
        let message: JSONValue
        do {
            message = try JSONDecoder().decode(JSONValue.self, from: body)
        } catch {
            return Self.failure(status: 400, id: nil, code: ErrorCode.parseError, message: "Parse error: the body is not valid JSON.")
        }

        guard case .object = message else {
            return Self.failure(status: 400, id: nil, code: ErrorCode.invalidRequest, message: "Invalid request: batches are not supported; send one JSON-RPC message per POST.")
        }

        // Notifications and responses from the client need no reply.
        guard let method = message["method"]?.stringValue, let id = message["id"], id != .null else {
            return MCPHTTPResponse(status: 202, body: nil, sessionID: nil)
        }
        let params = message["params"] ?? [:]

        switch method {
        case "initialize":
            return await initialize(id: id, params: params)
        case "ping":
            return Self.success(id: id, result: [:])
        case "tools/list":
            let definitions = await tools.definitions
            return Self.success(id: id, result: ["tools": .array(definitions.map(Self.json(for:)))])
        case "tools/call":
            return await callTool(id: id, params: params, sessionID: sessionID)
        default:
            return Self.failure(status: 200, id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method)")
        }
    }

    // MARK: - Methods

    private func initialize(id: JSONValue, params: JSONValue) async -> MCPHTTPResponse {
        let requested = params["protocolVersion"]?.stringValue
        let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.supportedProtocolVersions[0]
        let clientName = params["clientInfo"]?["name"]?.stringValue
        let sessionID = await sessions.createSession(clientName: clientName)
        let instructions = await tools.instructions

        var response = Self.success(id: id, result: [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "ManualTestPlan", "version": .string(serverVersion)],
            "instructions": .string(instructions)
        ])
        response.sessionID = sessionID
        return response
    }

    private func callTool(id: JSONValue, params: JSONValue, sessionID: String?) async -> MCPHTTPResponse {
        guard let name = params["name"]?.stringValue else {
            return Self.failure(status: 200, id: id, code: ErrorCode.invalidParams, message: "Invalid params: 'name' is required.")
        }
        let definitions = await tools.definitions
        guard definitions.contains(where: { $0.name == name }) else {
            return Self.failure(status: 200, id: id, code: ErrorCode.invalidParams, message: "Unknown tool: \(name)")
        }

        let arguments = params["arguments"].flatMap { $0 == .null ? nil : $0 } ?? [:]
        let context = MCPCallContext(clientName: await sessions.clientName(for: sessionID))
        let result = await tools.call(name: name, arguments: arguments, context: context)

        let content: [JSONValue] = result.content.map { block in
            switch block {
            case .text(let text):
                ["type": "text", "text": .string(text)]
            case .image(let data, let mimeType):
                ["type": "image", "data": .string(data.base64EncodedString()), "mimeType": .string(mimeType)]
            }
        }
        return Self.success(id: id, result: ["content": .array(content), "isError": .bool(result.isError)])
    }

    // MARK: - Encoding

    private enum ErrorCode {
        static let parseError = -32700
        static let invalidRequest = -32600
        static let methodNotFound = -32601
        static let invalidParams = -32602
    }

    private static func json(for definition: MCPToolDefinition) -> JSONValue {
        [
            "name": .string(definition.name),
            "description": .string(definition.description),
            "inputSchema": definition.inputSchema
        ]
    }

    private static func success(id: JSONValue, result: JSONValue) -> MCPHTTPResponse {
        encode(["jsonrpc": "2.0", "id": id, "result": result], status: 200)
    }

    private static func failure(status: Int, id: JSONValue?, code: Int, message: String) -> MCPHTTPResponse {
        encode([
            "jsonrpc": "2.0",
            "id": id ?? .null,
            "error": ["code": .int(code), "message": .string(message)]
        ], status: status)
    }

    private static func encode(_ value: JSONValue, status: Int) -> MCPHTTPResponse {
        MCPHTTPResponse(status: status, body: try? JSONEncoder().encode(value), sessionID: nil)
    }
}

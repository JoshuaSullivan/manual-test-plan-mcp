//
//  MCPHTTPHandler.swift
//  ManualTestPlan
//

import Foundation

/// Applies the MCP Streamable HTTP rules to a parsed request and produces the response.
///
/// Endpoint: `POST /mcp` carries one JSON-RPC message. `DELETE /mcp` ends a session. There is no
/// server-to-client stream, so `GET /mcp` answers `405` as the specification allows.
///
/// Security: the server listens on loopback only, but a web page in the user's browser can still reach
/// loopback ports. To block that (DNS rebinding and cross-site requests), requests must carry a `Host`
/// that names this exact loopback address and port, and any request with an `Origin` header is refused.
/// Native MCP clients don't send `Origin`.
nonisolated struct MCPHTTPHandler: Sendable {
    /// The path agents connect to.
    static let endpointPath = "/mcp"

    private let router: MCPRouter
    private let allowedHosts: Set<String>

    /// Creates a handler.
    /// - Parameters:
    ///   - router: Processes JSON-RPC messages.
    ///   - port: The port the server listens on, used to validate the `Host` header.
    init(router: MCPRouter, port: UInt16) {
        self.router = router
        self.allowedHosts = ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)"]
    }

    /// Produces the response for one request.
    /// - Parameter request: The parsed request.
    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard let host = request.header("host")?.lowercased(), allowedHosts.contains(host) else {
            return .text(403, "Forbidden: unexpected Host header.")
        }
        guard request.header("origin") == nil else {
            return .text(403, "Forbidden: browser-originated requests are not allowed.")
        }
        guard request.path == Self.endpointPath else {
            return .text(404, "Not found. The MCP endpoint is \(Self.endpointPath).")
        }

        switch request.method {
        case "POST":
            return await post(request)
        case "DELETE":
            if let sessionID = request.header("mcp-session-id") {
                await router.endSession(sessionID)
            }
            return HTTPResponse(status: 200)
        default:
            return .text(405, "Method not allowed.", headers: ["Allow": "POST, DELETE"])
        }
    }

    private func post(_ request: HTTPRequest) async -> HTTPResponse {
        guard !request.body.isEmpty else {
            return .text(400, "Empty request body.")
        }
        let reply = await router.handle(body: request.body, sessionID: request.header("mcp-session-id"))
        var response = HTTPResponse(status: reply.status)
        if let body = reply.body {
            response.body = body
            response.headers["Content-Type"] = "application/json"
        }
        if let sessionID = reply.sessionID {
            response.headers["Mcp-Session-Id"] = sessionID
        }
        return response
    }
}

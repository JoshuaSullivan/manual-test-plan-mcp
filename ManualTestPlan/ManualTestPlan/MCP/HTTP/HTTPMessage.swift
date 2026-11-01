//
//  HTTPMessage.swift
//  ManualTestPlan
//

import Foundation

/// A parsed HTTP/1.1 request.
nonisolated struct HTTPRequest: Sendable, Equatable {
    /// Upper-case method, such as `POST`.
    var method: String
    /// The request target exactly as sent, including any query string.
    var target: String
    /// Header values keyed by lower-cased name.
    var headers: [String: String]
    /// The request body (empty if none).
    var body: Data

    /// The path portion of ``target``, without query or fragment.
    var path: String {
        String(target.prefix { $0 != "?" && $0 != "#" })
    }

    /// A header value by case-insensitive name.
    /// - Parameter name: The header name.
    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// An HTTP/1.1 response to serialize onto the wire.
nonisolated struct HTTPResponse: Sendable, Equatable {
    /// Status code, such as `200`.
    var status: Int
    /// Extra headers. `Content-Length` and `Connection` are added during serialization.
    var headers: [String: String] = [:]
    /// The body (empty if none).
    var body = Data()
    /// Whether to tell the client the connection will close after this response.
    var closesConnection = false

    /// A plain-text response, convenient for errors.
    /// - Parameters:
    ///   - status: The status code.
    ///   - message: A one-line explanation for the client.
    ///   - headers: Extra headers.
    static func text(_ status: Int, _ message: String, headers: [String: String] = [:]) -> HTTPResponse {
        var headers = headers
        headers["Content-Type"] = "text/plain; charset=utf-8"
        return HTTPResponse(status: status, headers: headers, body: Data((message + "\n").utf8))
    }

    /// The bytes to write to the socket.
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = closesConnection ? "close" : "keep-alive"
        for (name, value) in all.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 100: "Continue"
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Content Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 505: "HTTP Version Not Supported"
        default: "Status \(status)"
        }
    }
}

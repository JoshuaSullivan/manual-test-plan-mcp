//
//  HTTPRequestParser.swift
//  ManualTestPlan
//

import Foundation

/// The result of trying to parse one request from the front of a receive buffer.
nonisolated enum HTTPParseOutcome: Sendable, Equatable {
    /// More bytes are needed. `expectsContinue` is true when the client sent `Expect: 100-continue`
    /// and is waiting for permission before sending the body.
    case incomplete(expectsContinue: Bool)
    /// A full request was parsed from the first `bytesConsumed` bytes.
    case complete(HTTPRequest, bytesConsumed: Int)
    /// The bytes can never form a valid request; answer with this response and close the connection.
    case rejected(HTTPResponse)
}

/// A minimal HTTP/1.1 request parser: request line, headers, and a `Content-Length` body.
///
/// It deliberately supports nothing else (no chunked bodies, no upgrades), and enforces size limits so a
/// misbehaving local client can't make the app buffer unbounded data.
nonisolated enum HTTPRequestParser {
    /// Largest accepted request line plus headers.
    static let maxHeaderBytes = 16 * 1024
    /// Largest accepted body. Tool calls carry text only, so this is generous.
    static let maxBodyBytes = 4 * 1024 * 1024

    private static let terminator = Data("\r\n\r\n".utf8)

    /// Parses the first request in `buffer`, if it is complete.
    /// - Parameter buffer: Bytes received so far, starting at the beginning of a request.
    static func parse(_ buffer: Data) -> HTTPParseOutcome {
        guard let end = buffer.range(of: terminator) else {
            return buffer.count > maxHeaderBytes
                ? .rejected(reject(431, "Request headers are too large."))
                : .incomplete(expectsContinue: false)
        }
        guard end.lowerBound - buffer.startIndex <= maxHeaderBytes else {
            return .rejected(reject(431, "Request headers are too large."))
        }

        let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3 else {
            return .rejected(reject(400, "Malformed request line."))
        }
        guard requestLine[2].hasPrefix("HTTP/1.") else {
            return .rejected(reject(505, "Only HTTP/1.x is supported."))
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                return .rejected(reject(400, "Malformed header line."))
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .rejected(reject(400, "Malformed header line.")) }
            headers[name] = value
        }

        if headers["transfer-encoding"] != nil {
            return .rejected(reject(501, "Chunked and other transfer encodings are not supported; send Content-Length."))
        }

        var length = 0
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0 else {
                return .rejected(reject(400, "Invalid Content-Length."))
            }
            guard parsed <= maxBodyBytes else {
                return .rejected(reject(413, "Request body is too large."))
            }
            length = parsed
        }

        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else {
            let expects = headers["expect"]?.lowercased() == "100-continue"
            return .incomplete(expectsContinue: expects)
        }

        let request = HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            target: String(requestLine[1]),
            headers: headers,
            body: Data(buffer[bodyStart..<(bodyStart + length)])
        )
        return .complete(request, bytesConsumed: bodyStart + length - buffer.startIndex)
    }

    private static func reject(_ status: Int, _ message: String) -> HTTPResponse {
        var response = HTTPResponse.text(status, message)
        response.closesConnection = true
        return response
    }
}

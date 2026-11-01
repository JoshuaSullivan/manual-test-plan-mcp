//
//  HTTPRequestParserTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

struct HTTPRequestParserTests {
    private func raw(_ text: String) -> Data { Data(text.utf8) }

    private func post(body: String, extraHeaders: String = "") -> String {
        "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:1\r\nContent-Length: \(body.utf8.count)\r\n\(extraHeaders)\r\n\(body)"
    }

    private func expectComplete(_ outcome: HTTPParseOutcome) throws -> (HTTPRequest, Int) {
        guard case .complete(let request, let consumed) = outcome else {
            Issue.record("expected .complete, got \(outcome)")
            throw CancellationError()
        }
        return (request, consumed)
    }

    @Test func parsesARequestWithABody() throws {
        let text = post(body: #"{"a":1}"#, extraHeaders: "Mcp-Session-Id: abc\r\n")
        let (request, consumed) = try expectComplete(HTTPRequestParser.parse(raw(text)))

        #expect(request.method == "POST")
        #expect(request.target == "/mcp")
        #expect(request.header("HOST") == "127.0.0.1:1")
        #expect(request.header("mcp-session-id") == "abc")
        #expect(request.body == raw(#"{"a":1}"#))
        #expect(consumed == text.utf8.count)
    }

    @Test func parsesABodylessRequest() throws {
        let text = "GET /mcp?x=1 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let (request, consumed) = try expectComplete(HTTPRequestParser.parse(raw(text)))
        #expect(request.method == "GET")
        #expect(request.path == "/mcp")
        #expect(request.body.isEmpty)
        #expect(consumed == text.utf8.count)
    }

    @Test func everyProperPrefixIsIncomplete() {
        let text = post(body: #"{"hello":"world"}"#)
        let bytes = raw(text)
        for length in 0..<bytes.count {
            let outcome = HTTPRequestParser.parse(bytes.prefix(length).withUnsafeBytes { Data($0) })
            #expect(outcome == .incomplete(expectsContinue: false), "prefix of \(length) bytes")
        }
    }

    @Test func leavesPipelinedBytesUnconsumed() throws {
        let first = post(body: "one")
        let second = post(body: "two")
        let buffer = raw(first + second)

        let (request, consumed) = try expectComplete(HTTPRequestParser.parse(buffer))
        #expect(request.body == raw("one"))
        #expect(consumed == first.utf8.count)

        let rest = Data(buffer.dropFirst(consumed))
        let (next, _) = try expectComplete(HTTPRequestParser.parse(rest))
        #expect(next.body == raw("two"))
    }

    @Test func worksOnDataSlices() throws {
        let prefixed = raw("JUNK" + post(body: "body"))
        let slice = prefixed.dropFirst(4)
        let (request, consumed) = try expectComplete(HTTPRequestParser.parse(slice))
        #expect(request.body == raw("body"))
        #expect(consumed == slice.count)
    }

    @Test func reportsExpectContinueWhileTheBodyIsMissing() {
        let head = "POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Length: 100\r\nExpect: 100-continue\r\n\r\n"
        #expect(HTTPRequestParser.parse(raw(head)) == .incomplete(expectsContinue: true))
    }

    @Test func headerNamesAreCaseInsensitiveAndValuesTrimmed() throws {
        let text = "POST /mcp HTTP/1.1\r\nhOsT:   localhost:9  \r\ncontent-length: 0\r\n\r\n"
        let (request, _) = try expectComplete(HTTPRequestParser.parse(raw(text)))
        #expect(request.header("Host") == "localhost:9")
    }

    private func rejection(_ text: String) -> HTTPResponse? {
        guard case .rejected(let response) = HTTPRequestParser.parse(raw(text)) else { return nil }
        return response
    }

    @Test func rejectsMalformedInput() {
        #expect(rejection("NONSENSE\r\n\r\n")?.status == 400)
        #expect(rejection("GET / HTTP/1.1\r\nno-colon-here\r\n\r\n")?.status == 400)
        #expect(rejection("GET / HTTP/1.1\r\n: empty-name\r\n\r\n")?.status == 400)
        #expect(rejection("POST / HTTP/1.1\r\nContent-Length: abc\r\n\r\n")?.status == 400)
        #expect(rejection("POST / HTTP/1.1\r\nContent-Length: -5\r\n\r\n")?.status == 400)
        #expect(rejection("GET / HTTP/2.0\r\n\r\n")?.status == 505)
    }

    @Test func rejectsChunkedBodies() {
        let response = rejection("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")
        #expect(response?.status == 501)
        #expect(response?.closesConnection == true)
    }

    @Test func enforcesSizeLimits() {
        let tooBig = "POST /mcp HTTP/1.1\r\nContent-Length: \(HTTPRequestParser.maxBodyBytes + 1)\r\n\r\n"
        #expect(rejection(tooBig)?.status == 413)

        let endlessHeader = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPRequestParser.maxHeaderBytes)
        #expect(rejection(endlessHeader)?.status == 431)

        let hugeCompleteHeader = endlessHeader + "\r\n\r\n"
        #expect(rejection(hugeCompleteHeader)?.status == 431)
    }

    @Test func serializesResponses() {
        var response = HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: raw("{}"))
        var text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(text.contains("Connection: keep-alive\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{}"))

        response = .text(403, "no")
        response.closesConnection = true
        text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 403 Forbidden\r\n"))
        #expect(text.contains("Connection: close\r\n"))
    }
}

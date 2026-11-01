//
//  MCPServer.swift
//  ManualTestPlan
//

import Foundation
import Network
import Observation
import OSLog

/// Hosts the MCP endpoint on `127.0.0.1:<port>`.
///
/// The server binds to the loopback interface only, so it is unreachable from other machines. See
/// ``MCPHTTPHandler`` for the additional checks that keep local web pages out.
@MainActor
@Observable
final class MCPServer {
    /// Where the server is in its lifecycle.
    enum State: Equatable {
        /// Not listening.
        case stopped
        /// Binding the port.
        case starting
        /// Accepting connections on this port.
        case running(port: UInt16)
        /// Could not listen; the message is suitable for showing to the user.
        case failed(String)
    }

    /// The current state, for display in the menu bar and settings.
    private(set) var state: State = .stopped

    @ObservationIgnored private let router: MCPRouter
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.joshuasullivan.ManualTestPlan", category: "Server")

    private static let receiveChunkSize = 64 * 1024

    /// Creates a stopped server.
    /// - Parameter router: Handles the JSON-RPC messages the server receives.
    init(router: MCPRouter) {
        self.router = router
    }

    /// Starts listening, first stopping any previous listener.
    /// - Parameter port: The loopback port to bind.
    func start(port: UInt16) {
        stop()
        state = .starting
        let handler = MCPHTTPHandler(router: router, port: port)
        listenTask = Task { [weak self] in
            guard let self else { return }
            do {
                let parameters = NWParametersBuilder<TCP>.parameters { TCP() }
                    .localEndpoint(.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any))
                    .localEndpointReuseAllowed(true)
                // No connection limit: NetworkListener's limit counts every connection ever accepted, not
                // concurrent ones, so any cap would silently stop the server after that many requests.
                let listener = try NetworkListener<TCP>(using: parameters)
                    .onStateUpdate { [weak self] _, newState in
                        self?.listenerStateChanged(newState, port: port)
                    }
                try await listener.run { connection in
                    await Self.serve(connection, handler: handler)
                }
                // run() returns when the listener is cancelled.
                if case .starting = state { state = .stopped }
            } catch is CancellationError {
                // stop() was called.
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(Self.describe(error, port: port))
            }
        }
    }

    /// Stops listening and drops open connections.
    func stop() {
        listenTask?.cancel()
        listenTask = nil
        state = .stopped
    }

    private func listenerStateChanged(_ listenerState: NetworkListener<TCP>.State, port: UInt16) {
        guard listenTask != nil else { return }
        switch listenerState {
        case .ready:
            state = .running(port: port)
            logger.info("Listening on 127.0.0.1:\(port, privacy: .public)")
        case .failed(let error):
            state = .failed(Self.describe(error, port: port))
        case .waiting(let error):
            state = .failed(Self.describe(error, port: port))
        case .setup, .cancelled:
            break
        @unknown default:
            break
        }
    }

    private static func describe(_ error: any Error, port: UInt16) -> String {
        if let error = error as? NWError, case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(port) is already in use. Choose another port in Settings."
        }
        return "Could not listen on port \(port): \(error.localizedDescription)"
    }

    // MARK: - Connections

    /// Serves one client connection until it closes or sends something unparseable.
    ///
    /// Requests are handled one at a time, in order, with HTTP keep-alive.
    @concurrent
    private static func serve(_ connection: NetworkConnection<TCP>, handler: MCPHTTPHandler) async {
        var buffer = Data()
        var sentContinue = false
        do {
            while !Task.isCancelled {
                switch HTTPRequestParser.parse(buffer) {
                case .incomplete(let expectsContinue):
                    if expectsContinue, !sentContinue {
                        sentContinue = true
                        try await connection.send(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8))
                    }
                    let message = try await connection.receive(atLeast: 1, atMost: receiveChunkSize)
                    guard !message.content.isEmpty else { return }
                    buffer.append(message.content)

                case .complete(let request, let consumed):
                    buffer = Data(buffer.dropFirst(consumed))
                    sentContinue = false
                    var response = await handler.handle(request)
                    let closes = request.header("connection")?.lowercased() == "close"
                    response.closesConnection = closes
                    try await connection.send(response.serialized(), endOfStream: closes)
                    if closes { return }

                case .rejected(let response):
                    try await connection.send(response.serialized(), endOfStream: true)
                    return
                }
            }
        } catch {
            // The client went away or the connection failed; nothing to report.
        }
    }
}

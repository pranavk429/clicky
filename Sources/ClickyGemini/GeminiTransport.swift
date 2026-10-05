import Foundation

/// One bidirectional frame pipe. Implementations: `URLSessionWebSocketTransport`
/// (production/hackathon), `FakeTransport` (Tests/ClickyGeminiTests), `MockSession`
/// (shipped demo fallback).
public protocol GeminiTransport: Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

public enum GeminiTransportError: Error, Equatable {
    case closed
    case unsupportedMessage
}

/// Thin `URLSessionWebSocketTask` wrapper — the only production transport (spec §5:
/// no third-party SDK; the legacy Swift SDK is deprecated and has no Live support).
public actor URLSessionWebSocketTransport: GeminiTransport {
    private let task: URLSessionWebSocketTask

    public init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
    }

    public func connect() async throws { task.resume() }

    public func send(_ data: Data) async throws { try await task.send(.data(data)) }

    public func receive() async throws -> Data {
        let message = try await task.receive()
        switch message {
        case .data(let data): return data
        case .string(let string): return Data(string.utf8)
        @unknown default: throw GeminiTransportError.unsupportedMessage
        }
    }

    public func close() async { task.cancel(with: .normalClosure, reason: nil) }
}

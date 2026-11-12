import Foundation
import Network
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPConnectionTests {
    @Test(.timeLimit(.minutes(1))) func releaseWhenClose() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.cancel()
        }
        defer { listener.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Swift.Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
        listener.stateUpdateHandler = nil
        let port = try #require(listener.port)
        weak var weakConnection: RTMPConnection?
        await {
            let connection = RTMPConnection()
            weakConnection = connection
            _ = try? await connection.connect("rtmp://127.0.0.1:\(port.rawValue)/live")
            try? await connection.close()
        }()
        #expect(weakConnection == nil)
    }
}

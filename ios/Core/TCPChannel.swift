import Foundation
import Network

private final class CompletionGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    func finish(_ result: Result<T, Error>) {
        lock.lock(); let saved = continuation; continuation = nil; lock.unlock()
        saved?.resume(with: result)
    }
}

protocol CameraChannel: AnyObject, Sendable {
    func open() async throws
    func close()
    func send(_ frame: PTPFrame) async throws
    func packet(deadline: Date?) async throws -> PTPFrame
}

final class TCPChannel: CameraChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "cc.huevia.ios.ptpip")
    init(host: String, port: UInt16) {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        parameters.prohibitExpensivePaths = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
    }
    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = CompletionGate(continuation)
            let timeout = DispatchWorkItem { [connection] in connection.cancel(); gate.finish(.failure(HueviaError("连接超时，请确认 iPhone 已加入相机 Wi‑Fi，并允许本地网络访问。"))) }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: timeout.cancel(); gate.finish(.success(()))
                case .failed(let error): timeout.cancel(); gate.finish(.failure(error))
                case .cancelled: timeout.cancel(); gate.finish(.failure(HueviaError("连接已取消。")))
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 12, execute: timeout)
            connection.start(queue: queue)
        }
    }
    func close() { connection.cancel() }
    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = CompletionGate(continuation)
            let timeout = DispatchWorkItem { [connection] in connection.cancel(); gate.finish(.failure(HueviaError("相机发送超时，已停止连接。"))) }
            queue.asyncAfter(deadline: .now() + 20, execute: timeout)
            connection.send(content: data, completion: .contentProcessed { error in
                timeout.cancel()
                if let error { gate.finish(.failure(error)) } else { gate.finish(.success(())) }
            })
        }
    }
    func readExactly(_ count: Int, deadline: Date?) async throws -> Data {
        guard count >= 0, count <= 1_048_584 else { throw HueviaError("相机接收长度无效。") }
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let gate = CompletionGate(continuation)
                let timeout: DispatchWorkItem? = deadline.map { deadline in
                    let work = DispatchWorkItem { [connection] in connection.cancel(); gate.finish(.failure(HueviaError("相机响应超时，已停止连接。"))) }
                    queue.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: work)
                    return work
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    timeout?.cancel()
                    if let error { gate.finish(.failure(error)) }
                    else if let data, !data.isEmpty { gate.finish(.success(data)) }
                    else { gate.finish(.failure(HueviaError(complete ? "相机连接已关闭。" : "相机没有返回完整数据。"))) }
                }
            }
            result.append(chunk)
        }
        return result
    }
    func packet(deadline: Date?) async throws -> PTPFrame {
        let headerData = try await readExactly(8, deadline: deadline)
        let h = try PTPFrame.header(headerData)
        return PTPFrame(type: h.type, payload: try await readExactly(h.length - 8, deadline: deadline))
    }
    func send(_ frame: PTPFrame) async throws { try await send(frame.encoded()) }
}

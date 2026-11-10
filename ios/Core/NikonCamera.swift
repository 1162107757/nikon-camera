import Foundation

public struct CameraSlot: Identifiable, Sendable {
    public let id: UInt32
    public let data: Data
    public let name: String
    public var label: String { "C\(id - 200)" }
    public var isEmpty: Bool { data.count >= 2 && data[0] == 0 && data[1] == 0 }
    public init(id: UInt32, data: Data) throws {
        guard (201...209).contains(id) else { throw HueviaError("只能选择 C1–C9 槽位。") }
        self.id = id; self.data = data; name = try NCPConverter.registrationName(data)
    }
}

public struct CameraSnapshot: Sendable {
    public let token: UUID
    public let info: CameraInfo
    public let standard: Data
    public let slots: [CameraSlot]
}

/// Isolated command owner: one confirmed registration, exact readback, explicit refresh before rearming.
public actor NikonCamera {
    private let factory: @Sendable (String, UInt16) -> any CameraChannel
    private let drainEvents: Bool
    private var command: (any CameraChannel)?
    private var events: (any CameraChannel)?
    private var eventTask: Task<Void, Never>?
    private var token = UUID()
    private var nextTransaction: UInt32 = 1
    private var sessionOpen = false
    private var busy = false
    private var writeAttempted = false
    private var verified = false
    private var lastSnapshot: CameraSnapshot?

    public init() { factory = { TCPChannel(host: $0, port: $1) }; drainEvents = true }
    init(factory: @escaping @Sendable (String, UInt16) -> any CameraChannel, drainEvents: Bool) {
        self.factory = factory; self.drainEvents = drainEvents
    }
    public func isConnected() -> Bool { command != nil && events != nil && sessionOpen }
    public func disconnect() { invalidate() }
    private func invalidate() {
        token = UUID(); sessionOpen = false; lastSnapshot = nil
        eventTask?.cancel(); eventTask = nil; command?.close(); events?.close(); command = nil; events = nil
    }
    private func check(_ expected: UUID) throws {
        guard expected == token, command != nil, !Task.isCancelled else { throw HueviaError("相机连接已取消或失效。") }
    }
    private func transaction() throws -> UInt32 {
        guard sessionOpen, nextTransaction < UInt32.max else { throw HueviaError("相机会话已失效，请重新连接。") }
        defer { nextTransaction += 1 }; return nextTransaction
    }
    public static func validHost(_ host: String) -> Bool {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return false }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }), numbers[3] > 0, numbers[3] < 255 else { return false }
        return numbers[0] == 10 || numbers[0] == 192 && numbers[1] == 168
            || numbers[0] == 172 && (16...31).contains(numbers[1]) || numbers[0] == 169 && numbers[1] == 254
    }
    public func connect(host: String, port: UInt16 = 15740, guid: Data) async throws -> CameraSnapshot {
        guard !busy else { throw HueviaError("相机操作进行中，请稍后重试。") }
        guard Self.validHost(host), port > 0, guid.count == 16 else { throw HueviaError("请填写相机 Wi‑Fi 的局域网 IPv4 地址和有效端口。") }
        busy = true; defer { busy = false }; invalidate()
        let expected = token; let c = factory(host, port); command = c
        do {
            try await c.open(); try check(expected)
            var initData = guid; initData.append(("Huevia iOS\0").data(using: .utf16LittleEndian)!); initData.put32(0x10000)
            try await c.send(PTPFrame(type: 1, payload: initData))
            let ack = try await c.packet(deadline: Date().addingTimeInterval(30))
            guard ack.type == 2, ack.payload.count >= 26, ack.payload.count <= 1024 else { throw HueviaError("相机未接受连接，请在相机上确认配对，使用“连接至电脑”模式。") }
            var reader = BinaryReader(ack.payload); let number = try reader.u32()
            _ = try reader.take(16); let peer = try reader.take(reader.remaining - 4)
            guard peer.count % 2 == 0, peer.suffix(2) == Data([0, 0]), try reader.u32() == 0x10000 else { throw HueviaError("相机握手格式不受支持。") }
            let e = factory(host, port); events = e; try await e.open(); try check(expected)
            var eventInit = Data(); eventInit.put32(number); try await e.send(PTPFrame(type: 3, payload: eventInit))
            let eventAck = try await e.packet(deadline: Date().addingTimeInterval(30))
            guard eventAck.type == 4, eventAck.payload.isEmpty else { throw HueviaError("相机事件通道建立失败。") }
            if drainEvents {
                eventTask = Task { [weak self, e] in
                    do {
                        while !Task.isCancelled {
                            let packet = try await e.packet(deadline: nil)
                            if packet.type == 13, packet.payload.isEmpty { try await e.send(PTPFrame(type: 14)) }
                            else if packet.type == 8, packet.payload.count >= 6, packet.payload.count <= 18 { continue }
                            else { throw HueviaError("相机事件通道已失效。") }
                        }
                    } catch { await self?.eventFailed(expected) }
                }
            }
            let info = try CameraInfo.parse(await data(0x1001, transaction: 0))
            guard info.supportsImport else { throw HueviaError("首版相机导入目前仅支持声明所需能力的 Nikon Z6II。") }
            try await sendCommand(0x1002, transaction: 0, parameters: [1]); sessionOpen = true; nextTransaction = 1
            writeAttempted = false; verified = false
            return try await snapshot(info: info, expected: expected)
        } catch { if token == expected { invalidate() }; throw error }
    }
    private func eventFailed(_ expected: UUID) { if token == expected { invalidate() } }
    public func refresh() async throws -> CameraSnapshot {
        guard !busy, isConnected(), !writeAttempted || verified, let saved = lastSnapshot else { throw HueviaError("请重新连接相机后读取槽位。") }
        busy = true; defer { busy = false }; let expected = token
        do {
            let result = try await snapshot(info: saved.info, expected: expected)
            writeAttempted = false; verified = false; return result
        } catch { invalidate(); throw error }
    }
    private func snapshot(info: CameraInfo, expected: UUID) async throws -> CameraSnapshot {
        let capability = try await data(0x90cf, transaction: transaction(), parameters: [1])
        guard capability.count == 28 else { throw HueviaError("相机优化校准能力格式不受支持。") }
        let standard = try await data(0x90cc, transaction: transaction(), parameters: [1, 0])
        _ = try NCPConverter.registrationName(standard)
        var slots = [CameraSlot]()
        for id in UInt32(201)...UInt32(209) {
            let bytes = try await data(0x90cc, transaction: transaction(), parameters: [id, 0])
            slots.append(try CameraSlot(id: id, data: bytes)); try check(expected)
        }
        let result = CameraSnapshot(token: expected, info: info, standard: standard, slots: slots)
        lastSnapshot = result; return result
    }
    public func importPreset(_ source: Data, to target: CameraSlot, snapshot confirmed: CameraSnapshot) async throws -> CameraSnapshot {
        guard !busy, isConnected(), !writeAttempted, confirmed.token == token,
              confirmed.slots.contains(where: { $0.id == target.id && $0.data == target.data }) else {
            throw HueviaError("槽位或会话已变化，请刷新槽位后重新确认。")
        }
        busy = true; defer { busy = false }; let expected = token
        do {
            let freshInfo = try CameraInfo.parse(await data(0x1001, transaction: transaction()))
            guard freshInfo.supportsImport, freshInfo.model == confirmed.info.model else { throw HueviaError("相机或导入能力发生变化。") }
            let capability = try await data(0x90cf, transaction: transaction(), parameters: [1])
            guard capability.count == 28 else { throw HueviaError("相机能力已变化。") }
            let standard = try await data(0x90cc, transaction: transaction(), parameters: [1, 0])
            guard standard == confirmed.standard else { throw HueviaError("相机标准模式参数已变化，请重新读取。") }
            let converted = try NCPConverter.convert(source, middle: Int(Int8(bitPattern: standard[26])), clarity: Int(Int8(bitPattern: standard[27])))
            for _ in 0..<2 {
                let current = try await data(0x90cc, transaction: transaction(), parameters: [target.id, 0])
                guard current == target.data else { throw HueviaError("目标槽位已被改动，本次没有写入，请重新读取。") }
            }
            try check(expected); let tx = try transaction(); writeAttempted = true; verified = false
            guard let c = command else { throw HueviaError("相机连接已失效。") }
            try await c.send(PTPFrame.request(0x90cd, transaction: tx, parameters: [target.id, 0], writing: true))
            var start = Data(); start.put32(tx); start.put64(UInt64(converted.bytes.count))
            try await c.send(PTPFrame(type: 9, payload: start))
            var end = Data(); end.put32(tx); end.append(converted.bytes)
            try await c.send(PTPFrame(type: 12, payload: end))
            try response(await control(deadline: Date().addingTimeInterval(30)), transaction: tx)
            let written = try await data(0x90cc, transaction: transaction(), parameters: [target.id, 0])
            guard written == converted.bytes else { throw HueviaError("相机读回结果与预设不一致。") }
            try check(expected); verified = true
            let result = CameraSnapshot(token: expected, info: freshInfo, standard: standard,
                slots: try confirmed.slots.map { $0.id == target.id ? try CameraSlot(id: target.id, data: written) : $0 })
            lastSnapshot = result; return result
        } catch {
            let uncertain = writeAttempted && !verified; invalidate()
            if uncertain { throw HueviaError("导入结果未确认，请先在相机检查该槽位，再重新连接；本次不会自动重试。\n" + error.localizedDescription) }
            throw error
        }
    }
    private func control(deadline: Date) async throws -> PTPFrame {
        guard let c = command else { throw HueviaError("相机连接已关闭。") }
        for _ in 0..<32 {
            let p = try await c.packet(deadline: deadline)
            if p.type == 13, p.payload.isEmpty { try await c.send(PTPFrame(type: 14)); continue }
            return p
        }
        throw HueviaError("相机返回了过多探测包。")
    }
    private func response(_ frame: PTPFrame, transaction: UInt32) throws {
        guard frame.type == 7, frame.payload.count >= 6, frame.payload.count <= 26, (frame.payload.count - 6) % 4 == 0 else { throw HueviaError("相机响应格式无效。") }
        var r = BinaryReader(frame.payload); let code = try r.u16(), tx = try r.u32()
        guard tx == transaction else { throw HueviaError("相机响应事务不一致。") }
        guard code == 0x2001 else { throw HueviaError(String(format: "相机拒绝操作（0x%04X），请检查连接模式和相机状态。", code)) }
    }
    private func sendCommand(_ op: UInt16, transaction tx: UInt32, parameters: [UInt32] = []) async throws {
        guard let c = command else { throw HueviaError("相机连接已关闭。") }
        try await c.send(PTPFrame.request(op, transaction: tx, parameters: parameters))
        try response(await control(deadline: Date().addingTimeInterval(30)), transaction: tx)
    }
    private func data(_ op: UInt16, transaction tx: UInt32, parameters: [UInt32] = []) async throws -> Data {
        guard let c = command else { throw HueviaError("相机连接已关闭。") }
        try await c.send(PTPFrame.request(op, transaction: tx, parameters: parameters))
        let deadline = Date().addingTimeInterval(30), first = try await control(deadline: Date().addingTimeInterval(30))
        if first.type == 7 { try response(first, transaction: tx); throw HueviaError("相机没有返回数据。") }
        guard first.type == 9, first.payload.count == 12 else { throw HueviaError("相机数据起始包无效。") }
        var r = BinaryReader(first.payload); guard try r.u32() == tx else { throw HueviaError("相机数据事务不符。") }
        let total = try r.u64(); guard total <= 1_048_576 else { throw HueviaError("相机数据超过接收上限。") }
        var bytes = Data(); var emptyPackets = 0
        while true {
            let p = try await control(deadline: deadline)
            guard p.type == 10 || p.type == 12, p.payload.count >= 4 else { throw HueviaError("相机数据包阶段不符。") }
            var payload = BinaryReader(p.payload); guard try payload.u32() == tx else { throw HueviaError("相机数据事务不符。") }
            let chunk = try payload.take(payload.remaining)
            guard UInt64(bytes.count + chunk.count) <= total else { throw HueviaError("相机数据长度超过声明。") }
            if chunk.isEmpty { emptyPackets += 1; guard emptyPackets <= 32 else { throw HueviaError("相机数据传输没有进展。") } }
            bytes.append(chunk)
            if p.type == 12 { break }
        }
        guard UInt64(bytes.count) == total else { throw HueviaError("相机数据传输未完成。") }
        try response(await control(deadline: deadline), transaction: tx); return bytes
    }
}

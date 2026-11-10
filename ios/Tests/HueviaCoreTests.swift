import XCTest
@testable import HueviaCore

final class HueviaCoreTests: XCTestCase {
    func testPacketHeaderAndTruncation() throws {
        let packet = try PTPFrame.request(0x90cc, transaction: 13, parameters: [201, 0])
        let bytes = try packet.encoded()
        XCTAssertEqual(try PTPFrame.header(bytes.prefix(8)).type, 6)
        XCTAssertEqual(Array(bytes.suffix(8)), [201, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertThrowsError(try PTPFrame.header(Data(repeating: 0, count: 8)))
        XCTAssertThrowsError(try PTPFrame.header(Data(repeating: 0, count: 7)))
        var reader = BinaryReader(Data([3, 65, 0, 0]))
        XCTAssertThrowsError(try reader.ptpString())
    }
    func testConverterMappingAndBounds() throws {
        let source = legacy()
        let converted = try NCPConverter.convert(source, middle: 3, clarity: -2)
        XCTAssertEqual(converted.name, "HUEVIA TEST")
        XCTAssertEqual(converted.bytes.count, 614)
        XCTAssertEqual(converted.bytes[0], 1)
        XCTAssertEqual(converted.bytes[25], 16)
        XCTAssertEqual(Int8(bitPattern: converted.bytes[27]), -2)
        XCTAssertEqual(converted.bytes[35], 1)
        XCTAssertEqual(converted.bytes.subdata(in: 36..<614), source.subdata(in: 56..<634))
        XCTAssertEqual(try NCPConverter.registrationName(converted.bytes), "HUEVIA TEST")
        for offset in [0, 12, 39, 41, 45, 56, 56 + 49, 634] {
            var bad = source; bad[offset] ^= 0xff
            XCTAssertThrowsError(try NCPConverter.convert(bad), "corruption offset \(offset)")
        }
        XCTAssertThrowsError(try NCPConverter.convert(source.dropLast()))
        XCTAssertThrowsError(try NCPConverter.convert(source, middle: 21))
        var badCurve = source; badCurve[120] = 0x80
        XCTAssertThrowsError(try NCPConverter.convert(badCurve))
    }
    func testHostAndDeviceAllowlist() throws {
        XCTAssertTrue(NikonCamera.validHost("192.168.1.1"))
        XCTAssertTrue(NikonCamera.validHost("172.16.0.1"))
        for host in ["8.8.8.8", "example.com", "192.168.1.999", "192.168.1.255", "172.32.1.1", "", "192.168.1"] { XCTAssertFalse(NikonCamera.validHost(host)) }
        XCTAssertTrue(try CameraInfo.parse(device()).supportsImport)
        XCTAssertFalse(try CameraInfo.parse(device(model: "Nikon Z 6" )).supportsImport)
        XCTAssertThrowsError(try CameraInfo.parse(device().dropLast()))
    }
    func testRealTransactionSequenceAndReadback() async throws {
        let rig = MockRig(), client = NikonCamera(factory: { _, _ in rig.make() }, drainEvents: false)
        let snapshot = try await client.connect(host: "192.168.1.1", guid: Data(repeating: 1, count: 16))
        XCTAssertEqual(snapshot.slots.count, 9)
        XCTAssertEqual(rig.command.writeCount, 0)
        let updated = try await client.importPreset(legacy(), to: snapshot.slots[0], snapshot: snapshot)
        XCTAssertEqual(rig.command.writeCount, 1)
        XCTAssertEqual(updated.slots[0].name, "HUEVIA TEST")
        do { _ = try await client.importPreset(legacy(), to: updated.slots[1], snapshot: updated); XCTFail("second write must require an explicit refresh") } catch { }
        XCTAssertEqual(rig.command.writeCount, 1)
        _ = try await client.refresh()
        await client.disconnect()
    }
    func testChangedSlotIsNeverOverwritten() async throws {
        let rig = MockRig(), client = NikonCamera(factory: { _, _ in rig.make() }, drainEvents: false)
        let snapshot = try await client.connect(host: "192.168.1.1", guid: Data(repeating: 2, count: 16))
        rig.command.slot = registration("CHANGED", base: 2)
        do { _ = try await client.importPreset(legacy(), to: snapshot.slots[0], snapshot: snapshot); XCTFail("stale slot must fail") } catch { }
        XCTAssertEqual(rig.command.writeCount, 0)
        let connected = await client.isConnected(); XCTAssertFalse(connected)
    }
    func testUnconfirmedWriteClosesSessionAndCannotRetry() async throws {
        let rig = MockRig(), client = NikonCamera(factory: { _, _ in rig.make() }, drainEvents: false)
        let snapshot = try await client.connect(host: "192.168.1.1", guid: Data(repeating: 3, count: 16))
        rig.command.corruptReadback = true
        do { _ = try await client.importPreset(legacy(), to: snapshot.slots[0], snapshot: snapshot); XCTFail("readback mismatch must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未确认")) }
        XCTAssertEqual(rig.command.writeCount, 1)
        let connected = await client.isConnected(); XCTAssertFalse(connected)
        do { _ = try await client.importPreset(legacy(), to: snapshot.slots[0], snapshot: snapshot); XCTFail("no implicit retry") } catch { }
        XCTAssertEqual(rig.command.writeCount, 1)
    }
    func testUnsupportedCameraNeverGetsVendorCommands() async throws {
        let rig = MockRig(); rig.command.model = "Nikon Z 7"
        let client = NikonCamera(factory: { _, _ in rig.make() }, drainEvents: false)
        do { _ = try await client.connect(host: "192.168.1.1", guid: Data(repeating: 4, count: 16)); XCTFail("unsupported camera") } catch { }
        XCTAssertFalse(rig.command.operations.contains(where: { $0 >= 0x9000 }))
    }
}

private func legacy() -> Data {
    var b = [UInt8](repeating: 0, count: 638)
    b.replaceSubrange(0..<4, with: [78, 67, 80, 0]); b[7] = 1; b[11] = 36
    b.replaceSubrange(12..<16, with: [48, 49, 48, 48]); b.replaceSubrange(16..<27, with: Array("HUEVIA TEST".utf8))
    b[37] = 1; b[38] = 2; b[39] = 255; b[40] = 132; b[41] = 1; b[42] = 1; b[43] = 128; b[44] = 128
    b[45] = 255; b[46] = 255; b[47] = 255; b[51] = 2; b[54] = 2; b[55] = 66
    b[56] = 0x49; b[57] = 0x30; b[64] = 2
    return Data(b)
}
private func registration(_ name: String, base: UInt8 = 0) -> Data {
    var data = Data(repeating: 0, count: 36); data[0] = base
    data.replaceSubrange(2..<(2 + name.utf8.count), with: name.utf8); return data
}
private func string(_ value: String) -> Data { var d = Data([UInt8(value.utf16.count + 1)]); d.append((value + "\0").data(using: .utf16LittleEndian)!); return d }
private func device(model: String = "Nikon Z6_2") -> Data {
    var d = Data(); d.put16(100); d.put32(10); d.put16(100); d.append(string("Nikon")); d.put16(0)
    let operations: [UInt16] = [0x1001, 0x1002, 0x1003, 0x90cc, 0x90cd, 0x90cf]
    d.put32(UInt32(operations.count)); for op in operations { d.put16(op) }
    for _ in 0..<4 { d.put32(0) }
    d.append(string("Nikon Corporation")); d.append(string(model)); d.append(string("1.0")); d.append(string("QA_ONLY")); return d
}
private final class MockRig: @unchecked Sendable {
    let command = MockChannel(), event = MockChannel()
    private let lock = NSLock(); private var index = 0
    func make() -> any CameraChannel { lock.lock(); defer { lock.unlock() }; index += 1; return index % 2 == 1 ? command : event }
}
private final class MockChannel: CameraChannel, @unchecked Sendable {
    var packets = [PTPFrame](), operations = [UInt16]()
    var slot = registration(""), model = "Nikon Z6_2", corruptReadback = false
    var writeCount = 0, pendingTarget: UInt32 = 0, pendingTx: UInt32 = 0
    func open() async throws { }
    func close() { }
    func packet(deadline: Date?) async throws -> PTPFrame { guard !packets.isEmpty else { throw HueviaError("QA empty packet queue") }; return packets.removeFirst() }
    func send(_ frame: PTPFrame) async throws {
        if frame.type == 1 {
            var d = Data(); d.put32(7); d.append(Data(repeating: 1, count: 16)); d.append(string("QA").dropFirst()); d.put32(0x10000)
            packets.append(PTPFrame(type: 2, payload: d)); return
        }
        if frame.type == 3 { packets.append(PTPFrame(type: 4)); return }
        if frame.type == 9 { return }
        if frame.type == 12 {
            var r = BinaryReader(frame.payload); let tx = try r.u32(); slot = try r.take(r.remaining)
            if corruptReadback { slot[25] ^= 1 }
            packets.append(ok(tx)); return
        }
        guard frame.type == 6 else { throw HueviaError("QA unexpected packet") }
        var r = BinaryReader(frame.payload); _ = try r.u32(); let op = try r.u16(), tx = try r.u32()
        var params = [UInt32](); while r.remaining > 0 { params.append(try r.u32()) }
        operations.append(op)
        if op == 0x90cd {
            guard params.count == 2, (201...209).contains(params[0]), params[1] == 0 else { throw HueviaError("unsafe write parameters") }
            writeCount += 1; pendingTarget = params[0]; pendingTx = tx; return
        }
        if op == 0x1002 || op == 0x1003 { packets.append(ok(tx)); return }
        let content: Data
        if op == 0x1001 { content = device(model: model) }
        else if op == 0x90cf { content = Data(repeating: 0, count: 28) }
        else if op == 0x90cc { content = params[0] == 1 ? registration("STANDARD", base: 1) : slot }
        else { throw HueviaError("QA unexpected operation") }
        var start = Data(); start.put32(tx); start.put64(UInt64(content.count))
        var end = Data(); end.put32(tx); end.append(content)
        packets += [PTPFrame(type: 9, payload: start), PTPFrame(type: 12, payload: end), ok(tx)]
    }
    private func ok(_ tx: UInt32) -> PTPFrame { var d = Data(); d.put16(0x2001); d.put32(tx); return PTPFrame(type: 7, payload: d) }
}

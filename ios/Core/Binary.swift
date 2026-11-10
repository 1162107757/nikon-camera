import Foundation

public struct HueviaError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct BinaryReader {
    private let bytes: [UInt8]
    public private(set) var offset = 0
    public init(_ data: Data) { bytes = Array(data) }
    public var remaining: Int { bytes.count - offset }
    public mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw HueviaError("数据不完整，请重新连接相机。") }
        defer { offset += count }
        return Data(bytes[offset ..< offset + count])
    }
    public mutating func u8() throws -> UInt8 { try take(1).first! }
    public mutating func u16() throws -> UInt16 {
        let b = Array(try take(2)); return UInt16(b[0]) | UInt16(b[1]) << 8
    }
    public mutating func u32() throws -> UInt32 {
        let b = Array(try take(4))
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }
    public mutating func u64() throws -> UInt64 {
        let lo = try u32(), hi = try u32(); return UInt64(lo) | UInt64(hi) << 32
    }
    public mutating func ptpString() throws -> String {
        let count = Int(try u8()); if count == 0 { return "" }
        let data = try take(count * 2)
        guard data.suffix(2) == Data([0, 0]), let value = String(data: data.dropLast(2), encoding: .utf16LittleEndian), !value.contains("\0") else {
            throw HueviaError("相机返回的文字格式不正确。")
        }
        return value
    }
    public mutating func array16() throws -> [UInt16] {
        let count = Int(try u32())
        guard count <= 4096, count <= remaining / 2 else { throw HueviaError("相机返回的列表过大或不完整。") }
        return try (0..<count).map { _ in try u16() }
    }
    public func requireEnd() throws { guard remaining == 0 else { throw HueviaError("相机数据包含未支持的附加内容。") } }
}

public extension Data {
    mutating func put16(_ n: UInt16) { append(UInt8(truncatingIfNeeded: n)); append(UInt8(truncatingIfNeeded: n >> 8)) }
    mutating func put32(_ n: UInt32) { for i in 0..<4 { append(UInt8(truncatingIfNeeded: n >> (i * 8))) } }
    mutating func put64(_ n: UInt64) { for i in 0..<8 { append(UInt8(truncatingIfNeeded: n >> (i * 8))) } }
}

public struct PTPFrame: Equatable {
    public let type: UInt32
    public let payload: Data
    public init(type: UInt32, payload: Data = Data()) { self.type = type; self.payload = payload }
    public func encoded() throws -> Data {
        guard payload.count <= 1_048_576 else { throw HueviaError("相机通信数据超过上限。") }
        var data = Data(); data.put32(UInt32(payload.count + 8)); data.put32(type); data.append(payload); return data
    }
    public static func header(_ data: Data) throws -> (length: Int, type: UInt32) {
        guard data.count == 8 else { throw HueviaError("相机通信头长度不符。") }
        var r = BinaryReader(data); let length = Int(try r.u32()), type = try r.u32()
        guard length >= 8, length <= 1_048_584 else { throw HueviaError("相机通信包超过上限。") }
        return (length, type)
    }
    public static func request(_ operation: UInt16, transaction: UInt32, parameters: [UInt32] = [], writing: Bool = false) throws -> PTPFrame {
        guard parameters.count <= 5 else { throw HueviaError("相机操作参数过多。") }
        var p = Data(); p.put32(writing ? 2 : 1); p.put16(operation); p.put32(transaction)
        for n in parameters { p.put32(n) }
        return PTPFrame(type: 6, payload: p)
    }
}

public struct CameraInfo: Sendable {
    public let manufacturer: String
    public let model: String
    public let firmware: String
    public let operations: Set<UInt16>
    public static func parse(_ data: Data) throws -> CameraInfo {
        var r = BinaryReader(data)
        _ = try r.u16(); _ = try r.u32(); _ = try r.u16(); _ = try r.ptpString(); _ = try r.u16()
        let ops = Set(try r.array16())
        for _ in 0..<4 { _ = try r.array16() }
        let maker = try r.ptpString(), model = try r.ptpString(), firmware = try r.ptpString()
        _ = try r.ptpString(); try r.requireEnd() // Serial number is never retained or logged.
        return CameraInfo(manufacturer: maker, model: model, firmware: firmware, operations: ops)
    }
    public var supportsImport: Bool {
        let compact = model.uppercased().filter { !$0.isWhitespace }
        return manufacturer.uppercased().contains("NIKON") && ["Z6_2", "NIKONZ6_2", "Z6II", "NIKONZ6II"].contains(compact)
            && Set<UInt16>([0x1002, 0x1003, 0x90cc, 0x90cd, 0x90cf]).isSubset(of: operations)
    }
}

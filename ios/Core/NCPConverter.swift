import Foundation
import CryptoKit

public struct ConvertedPreset: Sendable {
    public let name: String
    public let bytes: Data
}

public enum NCPConverter {
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func convert(_ source: Data, middle: Int = 0, clarity: Int = 0) throws -> ConvertedPreset {
        func reject(_ reason: String) -> HueviaError { HueviaError("此预设暂不支持 iOS 兼容导入：" + reason) }
        let b = Array(source)
        guard b.count == 638 else { throw reject("首版支持 638 字节的 NCP 0100 文件。") }
        func be16(_ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
        func be32(_ i: Int) -> UInt32 { UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3]) }
        guard Array(b[0..<4]) == [78, 67, 80, 0], be32(4) == 1, be32(8) == 36,
              be32(48) == 2, be32(52) == 578, be32(634) == 0, Array(b[12..<16]) == [48, 49, 48, 48] else {
            throw reject("文件头、版本或记录布局不符。")
        }
        let nameBytes = Array(b[16..<36])
        guard let end = nameBytes.firstIndex(of: 0), end > 0,
              nameBytes[..<end].allSatisfy({ (32...126).contains($0) }), nameBytes[end...].allSatisfy({ $0 == 0 }),
              let name = String(bytes: nameBytes[..<end], encoding: .ascii), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw reject("登记名称需要 1–19 个 ASCII 字符。")
        }
        let bases = [0x0001: 1, 0x03c2: 2, 0x00c3: 3, 0x0486: 5, 0x04c7: 6]
        guard let base = bases[be16(36)], b[38] <= 2, b[39] == 255 else { throw reject("基础类型或保留字段不符。") }
        let sharpening = Int(b[40]) - 128, saturation = Int(b[43]) - 128, hue = Int(b[44]) - 128
        guard (0...9).contains(sharpening), (-3...3).contains(saturation), (-3...3).contains(hue),
              b[41] == 1, b[42] == 1, b[45] == 255, b[46] == 255, b[47] == 255,
              (-20...20).contains(middle), (-20...20).contains(clarity) else { throw reject("参数包含首版尚未支持的特殊值。") }
        let curve = Array(b[56..<634])
        guard curve[0] == 0x49, curve[1] == 0x30, curve[6] <= 20, curve[7] <= 100,
              (2...20).contains(curve[8]), curve[49..<64].allSatisfy({ $0 == 0 }) else { throw reject("曲线头不符合已支持格式。") }
        for i in stride(from: 64, to: 578, by: 2) {
            guard Int(curve[i]) << 8 | Int(curve[i + 1]) <= 32767 else { throw reject("曲线采样超出范围。") }
        }
        var wire = [UInt8](repeating: 0, count: 614)
        wire[0] = UInt8(base); wire.replaceSubrange(2..<22, with: nameBytes)
        wire[25] = UInt8(sharpening * 4); wire[26] = UInt8(bitPattern: Int8(middle)); wire[27] = UInt8(bitPattern: Int8(clarity))
        wire[30] = UInt8(bitPattern: Int8(saturation * 4)); wire[31] = UInt8(bitPattern: Int8(hue * 4)); wire[35] = 1
        wire.replaceSubrange(36..<614, with: curve)
        return ConvertedPreset(name: name, bytes: Data(wire))
    }
    public static func registrationName(_ data: Data) throws -> String {
        let b = Array(data)
        guard b.count == 36 || b.count == 614, b[35] <= 1, b[35] == 0 || b.count == 614,
              let end = b[2..<22].firstIndex(of: 0), b[2..<end].allSatisfy({ $0 < 128 }) else {
            throw HueviaError("相机槽位的数据结构不受支持。")
        }
        return String(bytes: b[2..<end], encoding: .ascii) ?? ""
    }
}

import Foundation

/// A 3D .cube table. Entries preserve file order (red changes fastest).
/// Parsing alone does not choose the input/output color space or perform Log conversion.
public struct CubeLUT: Sendable {
    public let title: String?
    public let dimension: Int
    public let domainMin: [Float]
    public let domainMax: [Float]
    public let rgb: [Float]

    public enum ParseError: Error, LocalizedError, Equatable {
        case invalid(line: Int, reason: String)
        public var errorDescription: String? {
            switch self {
            case let .invalid(line, reason): return "LUT 第 \(line) 行：\(reason)"
            }
        }
    }

    public init(text: String) throws {
        var title: String?
        var size: Int?
        var minimum: [Float] = [0, 0, 0]
        var maximum: [Float] = [1, 1, 1]
        var values: [Float] = []
        var headers: Set<String> = []
        let lines = text.components(separatedBy: .newlines)
        for (offset, raw) in lines.enumerated() {
            let line = offset + 1
            // Comments outside quoted TITLE strings only.
            var quoted = false
            let body = raw.prefix { character in
                if character == "\"" { quoted.toggle() }
                return character != "#" || quoted
            }.trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }
            let parts = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let key = parts[0]
            func fail(_ reason: String) -> ParseError { .invalid(line: line, reason: reason) }
            func triple(_ tokens: [String]) throws -> [Float] {
                guard tokens.count == 3 else { throw fail("需要三个数值") }
                return try tokens.map {
                    guard let value = Float($0), value.isFinite else { throw fail("数值必须有限") }
                    return value
                }
            }
            if ["TITLE", "LUT_3D_SIZE", "DOMAIN_MIN", "DOMAIN_MAX"].contains(key) {
                guard values.isEmpty else { throw fail("头信息必须在色表之前") }
                guard headers.insert(key).inserted else { throw fail("头信息重复：\(key)") }
            }
            switch key {
            case "TITLE":
                let value = body.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                guard value.count >= 2, value.first == "\"", value.last == "\"" else {
                    throw fail("TITLE 必须使用双引号")
                }
                title = String(value.dropFirst().dropLast())
            case "LUT_3D_SIZE":
                guard parts.count == 2, let parsed = Int(parts[1]), (2...128).contains(parsed) else {
                    throw fail("当前支持 2–128 阶 3D LUT")
                }
                size = parsed
            case "DOMAIN_MIN": minimum = try triple(Array(parts.dropFirst()))
            case "DOMAIN_MAX": maximum = try triple(Array(parts.dropFirst()))
            case "LUT_1D_SIZE": throw fail("当前不支持 1D 或组合 LUT")
            default:
                guard let size else { throw fail("色表前缺少 LUT_3D_SIZE") }
                guard values.count < size * size * size * 3 else { throw fail("色表条目过多") }
                values.append(contentsOf: try triple(parts))
            }
        }
        guard let size else { throw ParseError.invalid(line: 1, reason: "缺少 LUT_3D_SIZE") }
        guard zip(minimum, maximum).allSatisfy({ $0 < $1 }) else {
            throw ParseError.invalid(line: 1, reason: "DOMAIN_MAX 必须逐通道大于 DOMAIN_MIN")
        }
        guard values.count == size * size * size * 3 else {
            throw ParseError.invalid(line: lines.count, reason: "色表不完整，需要 \(size * size * size) 条 RGB")
        }
        self.title = title
        dimension = size
        domainMin = minimum
        domainMax = maximum
        rgb = values
    }

    /// Float32 RGBA data for CIColorCube. Non-default domains need a separate
    /// input normalization stage; this data must not silently bypass that stage.
    public func rgbaData() -> Data {
        var rgba: [Float] = []
        rgba.reserveCapacity(dimension * dimension * dimension * 4)
        for index in stride(from: 0, to: rgb.count, by: 3) {
            rgba.append(contentsOf: rgb[index..<(index + 3)])
            rgba.append(1)
        }
        return rgba.withUnsafeBytes { Data($0) }
    }

    /// Portable copy for export recipes; retains domain and exact Float values.
    public func textRepresentation() -> String {
        var lines: [String] = []
        if let title { lines.append("TITLE \"\(title.replacingOccurrences(of: "\"", with: "'"))\"") }
        lines.append("LUT_3D_SIZE \(dimension)")
        lines.append("DOMAIN_MIN " + domainMin.map(String.init(describing:)).joined(separator: " "))
        lines.append("DOMAIN_MAX " + domainMax.map(String.init(describing:)).joined(separator: " "))
        for index in stride(from: 0, to: rgb.count, by: 3) {
            lines.append(rgb[index..<(index + 3)].map(String.init(describing:)).joined(separator: " "))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

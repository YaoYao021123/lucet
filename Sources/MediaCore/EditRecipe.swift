import CryptoKit
import Foundation

public struct LUTReference: Codable, Equatable, Sendable {
    public let file: String
    public let name: String
    public let encoding: LUTEncoding
}

public struct EditRecipe: Codable, Equatable, Sendable {
    public var version = 1
    public var adjustments = BasicAdjustments()
    public var degrees = 0.0
    public var geometry = GeometryAdjustments()
    public var strength = 1.0
    public var hdrEffect = false
    public var hdrPreview = true
    public var lut: LUTReference?
    public var clip: ClipSettings?
    public init() {}
    private enum CodingKeys: String, CodingKey { case version, adjustments, degrees, geometry, strength, hdrEffect, hdrPreview, lut, clip }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        adjustments = try values.decodeIfPresent(BasicAdjustments.self, forKey: .adjustments) ?? .init()
        geometry = try values.decodeIfPresent(GeometryAdjustments.self, forKey: .geometry) ?? .init()
        degrees = try values.decodeIfPresent(Double.self, forKey: .degrees) ?? 0
        strength = try values.decodeIfPresent(Double.self, forKey: .strength) ?? 1
        hdrEffect = try values.decodeIfPresent(Bool.self, forKey: .hdrEffect) ?? false
        hdrPreview = try values.decodeIfPresent(Bool.self, forKey: .hdrPreview) ?? true
        lut = try values.decodeIfPresent(LUTReference.self, forKey: .lut)
        clip = try values.decodeIfPresent(ClipSettings.self, forKey: .clip)
    }
    public func validate() throws {
        guard version == 1, adjustments == adjustments.sanitized, degrees.isFinite, (-10...10).contains(degrees),
              strength.isFinite, (0...1).contains(strength) else { throw VideoWorkError.failed("配方参数无效或版本不支持。") }
        try geometry.validate()
        if let clip { try clip.validate(duration: clip.end) }
        if let lut {
            guard lut.file.count == 69, lut.file.hasSuffix(".cube"),
                  lut.file.dropLast(5).allSatisfy({ $0.isHexDigit }) else { throw VideoWorkError.failed("LUT 引用无效。") }
        }
    }
    /// Copy chosen color groups only. Geometry, sound, range and HDR remain local.
    public func applying(from source: Self, groups: Set<AdjustmentGroup>, includeLUT: Bool) -> Self {
        var result = self
        for p in AdjustmentParameter.allCases where groups.contains(p.group) { result.adjustments[p] = source.adjustments[p] }
        if includeLUT { result.lut = source.lut; result.strength = source.strength }
        return result
    }
}

public struct SourceStamp: Codable, Equatable, Sendable {
    public let path: String
    public let bytes: Int
    public let modified: Date
    public init(_ url: URL) throws {
        // URL resource values can remain cached across an external file change.
        // Read a fresh stat for every identity check, including Live companions.
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              let bytes = (values[.size] as? NSNumber)?.intValue, let modified = values[.modificationDate] as? Date else {
            throw VideoWorkError.failed("无法读取原件身份信息。")
        }
        path = url.standardizedFileURL.path; self.bytes = bytes; self.modified = modified
    }
}

public struct DraftRecord: Codable, Sendable {
    public let source: SourceStamp
    public let companion: SourceStamp?
    public let recipe: EditRecipe
    public let savedAt: Date
}

/// Small atomic JSON recipes, with shared LUT files. Never writes to source media.
public struct DraftStore: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    public func location(for source: URL) -> URL {
        root.appendingPathComponent("drafts").appendingPathComponent(Self.digest(source.standardizedFileURL.path) + ".json")
    }
    public func storeLUT(_ lut: CreativeLUT) throws -> LUTReference {
        let text = lut.cube.textRepresentation()
        let file = Self.digest(text) + ".cube"
        let folder = root.appendingPathComponent("luts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: target.path) { try Data(text.utf8).write(to: target, options: .atomic) }
        return LUTReference(file: file, name: lut.name, encoding: lut.encoding)
    }
    public func loadLUT(_ reference: LUTReference) throws -> CreativeLUT {
        var recipe = EditRecipe(); recipe.lut = reference; try recipe.validate()
        let url = root.appendingPathComponent("luts").appendingPathComponent(reference.file)
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes < 100_000_000 else { throw VideoWorkError.failed("保存的 LUT 过大。") }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard Self.digest(text) + ".cube" == reference.file else { throw VideoWorkError.failed("保存的 LUT 校验失败。") }
        return CreativeLUT(cube: try CubeLUT(text: text), name: reference.name, encoding: reference.encoding)
    }
    public func save(_ recipe: EditRecipe, source: SourceStamp, companion: SourceStamp? = nil) throws {
        try recipe.validate()
        guard try SourceStamp(URL(fileURLWithPath: source.path)) == source,
              try companion.map({ try SourceStamp(URL(fileURLWithPath: $0.path)) == $0 }) ?? true else {
            throw VideoWorkError.failed("原件已变化，配方未自动覆盖；请重新打开素材。")
        }
        let target = location(for: URL(fileURLWithPath: source.path))
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(DraftRecord(source: source, companion: companion, recipe: recipe, savedAt: Date())).write(to: target, options: .atomic)
    }
    public func load(_ source: URL) throws -> EditRecipe? { try loadRecord(source)?.recipe }
    public func loadRecord(_ source: URL) throws -> DraftRecord? {
        let target = location(for: source)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let bytes = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes < 1_000_000 else { throw VideoWorkError.failed("配方文件过大。") }
        let record = try JSONDecoder().decode(DraftRecord.self, from: Data(contentsOf: target))
        guard record.source == (try SourceStamp(source)),
              try record.companion.map({ try SourceStamp(URL(fileURLWithPath: $0.path)) == $0 }) ?? true else {
            throw VideoWorkError.failed("原件或 Live 动态部分已变化，未套用旧配方。")
        }
        try record.recipe.validate()
        return record
    }
}

public struct EditHistory<Value: Equatable & Sendable>: Sendable {
    public private(set) var current: Value
    private var past: [Value] = []
    private var future: [Value] = []
    private var groupStart: Value?
    public init(_ value: Value) { current = value }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func beginGroup() { if groupStart == nil { groupStart = current } }
    public mutating func endGroup() {
        if let before = groupStart, before != current { appendPast(before); future = [] }
        groupStart = nil
    }
    public mutating func record(_ value: Value) {
        guard value != current else { return }
        if groupStart == nil { appendPast(current); future = [] }
        current = value
    }
    private mutating func appendPast(_ value: Value) {
        past.append(value); if past.count > 100 { past.removeFirst(past.count - 100) }
    }
    public mutating func undo() -> Value? {
        endGroup(); guard let previous = past.popLast() else { return nil }
        future.append(current); current = previous; return previous
    }
    public mutating func redo() -> Value? {
        guard let next = future.popLast() else { return nil }
        past.append(current); current = next; return next
    }
}

public struct SavedSnapshot: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let record: DraftRecord
}

extension DraftStore {
    private func snapshotFolder(_ source: URL) -> URL { root.appendingPathComponent("snapshots").appendingPathComponent(Self.digest(source.standardizedFileURL.path)) }
    @discardableResult public func saveSnapshot(_ recipe: EditRecipe, name: String, source: SourceStamp,
                                               companion: SourceStamp? = nil) throws -> SavedSnapshot {
        // The same identity checks as autosave apply to named versions.
        try save(recipe, source: source, companion: companion)
        let value = SavedSnapshot(id: UUID(), name: String(name.prefix(100)),
            record: DraftRecord(source: source, companion: companion, recipe: recipe, savedAt: Date()))
        let folder = snapshotFolder(URL(fileURLWithPath: source.path))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: folder.appendingPathComponent(value.id.uuidString + ".json"), options: .atomic)
        return value
    }
    public func snapshots(for source: URL) -> [SavedSnapshot] {
        let folder = snapshotFolder(source)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json", (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1_000_001 <= 1_000_000,
                  let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(SavedSnapshot.self, from: data) else { return nil }
            return value
        }.sorted { $0.record.savedAt > $1.record.savedAt }.prefix(50).map { $0 }
    }
    public func restoreSnapshot(_ snapshot: SavedSnapshot, for source: URL) throws -> EditRecipe {
        guard try SourceStamp(source) == snapshot.record.source,
              try snapshot.record.companion.map({ try SourceStamp(URL(fileURLWithPath: $0.path)) == $0 }) ?? true else {
            throw VideoWorkError.failed("原件或 Live 动态部分已变化，未恢复快照。")
        }
        try snapshot.record.recipe.validate()
        return snapshot.record.recipe
    }
}

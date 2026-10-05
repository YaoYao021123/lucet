import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum LUTEncoding: String, Sendable, CaseIterable, Codable {
    case sRGB, rec709 = "Rec.709"
    public var colorSpace: CGColorSpace {
        CGColorSpace(name: self == .sRGB ? CGColorSpace.sRGB : CGColorSpace.itur_709)!
    }
}

/// The encoding describes both sides of a display-to-display creative LUT.
/// Camera Log conversion remains a separate operation.
public struct CreativeLUT: Sendable, Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public let id: UUID
    public let name: String
    public let cube: CubeLUT
    public let data: Data
    public let encoding: LUTEncoding

    public init(cube: CubeLUT, name: String, encoding: LUTEncoding = .sRGB) {
        id = UUID(); self.name = name; self.cube = cube; data = cube.rgbaData(); self.encoding = encoding
    }

    public static let warm = builtIn(name: "暖调", warm: true)
    public static let soft = builtIn(name: "柔和", warm: false)

    private static func builtIn(name: String, warm: Bool) -> CreativeLUT {
        let size = 17
        var lines = ["TITLE \"\(name)\"", "LUT_3D_SIZE \(size)"]
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let values = [Double(r), Double(g), Double(b)].map { $0 / Double(size - 1) }
            let out = warm ? [min(1, values[0] * 1.04 + 0.015), values[1], values[2] * 0.94] : values.map { $0 * 0.90 + 0.04 }
            lines.append(out.map(String.init(describing:)).joined(separator: " "))
        } } }
        // Static tables are generated from finite values and a known dimension.
        return CreativeLUT(cube: try! CubeLUT(text: lines.joined(separator: "\n")), name: name)
    }
}

public struct MediaEdits: Sendable, Equatable {
    public var degrees: Double
    public var lut: CreativeLUT?
    public var strength: Double
    public var hdrEffect: Bool
    public var adjustments: BasicAdjustments
    public var geometry: GeometryAdjustments
    public init(degrees: Double = 0, lut: CreativeLUT? = nil, strength: Double = 1, hdrEffect: Bool = false, adjustments: BasicAdjustments = .init(), geometry: GeometryAdjustments = .init()) {
        self.degrees = degrees; self.lut = lut; self.strength = strength; self.hdrEffect = hdrEffect
        self.adjustments = adjustments.sanitized; self.geometry = geometry
    }
    public var hasGeometry: Bool { degrees != 0 || geometry.hasChanges }
    public var hasAdjustments: Bool { !adjustments.isNeutral }
    public var hasLUT: Bool { lut != nil && strength > 0 }
}

public enum ColorPipeline {
    public static let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    public static let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func context() -> CIContext {
        CIContext(options: [.workingColorSpace: linearSpace, .workingFormat: CIFormat.RGBAh.rawValue,
                            .cacheIntermediates: false])
    }

    public static func toneMap(_ image: CIImage, sourceHeadroom: Float, targetHeadroom: Float = 1) -> CIImage {
        guard sourceHeadroom > targetHeadroom else { return image }
        return image.applyingFilter("CIToneMapHeadroom", parameters: [
            "inputSourceHeadroom": sourceHeadroom, "inputTargetHeadroom": max(1, targetHeadroom)
        ])
    }

    public static func grade(_ image: CIImage, edits: MediaEdits, sourceHeadroom: Float = 1) throws -> CIImage {
        guard edits.hasLUT || edits.hasAdjustments else { return image }
        let base = try BasicColorPipeline.image(toneMap(image, sourceHeadroom: sourceHeadroom), adjustments: edits.adjustments)
        guard let lut = edits.lut, edits.strength > 0 else { return base }
        // Explicit conversion prevents applying a display LUT to linear-light RGB.
        let encoded = base.matchedFromWorkingSpace(to: lut.encoding.colorSpace)!
        let scales = zip(lut.cube.domainMin, lut.cube.domainMax).map { 1 / ($1 - $0) }
        let bias = zip(lut.cube.domainMin, scales).map { -$0 * $1 }
        let normalized = encoded.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scales[0]), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(scales[1]), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(scales[2]), w: 0),
            "inputBiasVector": CIVector(x: CGFloat(bias[0]), y: CGFloat(bias[1]), z: CGFloat(bias[2]), w: 0)
        ])
        let graded = normalized.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": lut.cube.dimension, "inputCubeData": lut.data
        ])
        let mixed = graded.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: encoded, kCIInputTimeKey: 1 - min(1, max(0, edits.strength))
        ])
        return mixed.matchedToWorkingSpace(from: lut.encoding.colorSpace)!.cropped(to: image.extent)
    }

    public static func geometry(_ image: CIImage, degrees: Double) throws -> CIImage {
        let input = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
        let plan = try StraighteningPlan(width: Int(input.extent.width.rounded()), height: Int(input.extent.height.rounded()),
                                        rotationRadians: degrees * .pi / 180)
        return input.transformed(by: plan.transform).cropped(to: plan.cropRect)
            .transformed(by: .init(translationX: -plan.cropRect.minX, y: -plan.cropRect.minY))
    }

    public static func sdrBitmap(_ image: CIImage, headroom: Float = 1, context: CIContext? = nil) throws -> CGImage {
        let mapped = toneMap(image, sourceHeadroom: headroom)
        guard let result = (context ?? self.context()).createCGImage(mapped, from: mapped.extent,
            format: .RGBA8, colorSpace: outputSpace) else { throw StraighteningError.renderFailed }
        return result
    }

    public static func exportPNG(_ url: URL, to output: URL, edits: MediaEdits) throws {
        try Task.checkCancellation()
        guard output.pathExtension.lowercased() == "png" else { throw StraighteningError.pngRequired }
        let input = try ImageGradeSession.decode(url)
        let graded = try grade(input, edits: edits, sourceHeadroom: max(1, input.contentHeadroom))
        let transformed = try geometry(graded, edits: edits)
        let bitmap = try sdrBitmap(transformed, headroom: (edits.hasLUT || edits.hasAdjustments) ? 1 : max(1, input.contentHeadroom))
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StraighteningError.renderFailed
        }
        CGImageDestinationAddImage(destination, bitmap, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StraighteningError.renderFailed }
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".workbench-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try (data as Data).write(to: temporary, options: .atomic)
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: output.path) else { throw VideoWorkError.outputExists }
        try FileManager.default.moveItem(at: temporary, to: output)
    }
    public static func exportPNGAsync(_ url: URL, to output: URL, edits: MediaEdits) async throws {
        let worker = Task.detached(priority: .userInitiated) { try exportPNG(url, to: output, edits: edits) }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}

public struct GradeFrame: Sendable {
    public let image: CIImage
    public let original: CIImage
    public let headroom: Float
    public let sourceHeadroom: Float
}

/// Decodes and materializes one bounded floating-point bitmap per opened image.
public actor ImageGradeSession {
    private let image: CIImage
    private let headroom: Float

    public init(url: URL, maximumDimension: Int = 1600) throws {
        let decoded = try Self.decode(url)
        headroom = max(1, decoded.contentHeadroom)
        let scale = min(1, CGFloat(maximumDimension) / max(decoded.extent.width, decoded.extent.height))
        let small = decoded.transformed(by: .init(scaleX: scale, y: scale))
        guard let bitmap = ColorPipeline.context().createCGImage(small, from: small.extent.integral,
            format: .RGBAh, colorSpace: ColorPipeline.linearSpace) else { throw StraighteningError.renderFailed }
        image = CIImage(cgImage: bitmap)
    }

    public static func decode(_ url: URL) throws -> CIImage {
        guard url.isFileURL, let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true, .expandToHDR: true]),
              !image.extent.isInfinite, !image.extent.isEmpty else { throw StraighteningError.unreadableImage }
        return image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    public func frame(edits: MediaEdits) throws -> GradeFrame {
        try Task.checkCancellation()
        let graded = try ColorPipeline.grade(image, edits: edits, sourceHeadroom: headroom)
        return GradeFrame(image: try ColorPipeline.geometry(graded, edits: edits), original: image,
                          headroom: (edits.hasLUT || edits.hasAdjustments) ? 1 : headroom, sourceHeadroom: headroom)
    }
}

import CoreImage
import Foundation

public struct GeometryAdjustments: Codable, Equatable, Sendable {
    public var quarterTurns = 0
    public var mirrored = false
    public var aspectRatio = 0.0
    public var cropScale = 1.0
    public var horizontal = 0.0
    public var vertical = 0.0
    public init() {}
    public var hasChanges: Bool { self != Self() }
    public func validate() throws {
        guard (0...3).contains(quarterTurns), aspectRatio.isFinite,
              aspectRatio == 0 || (0.25...4).contains(aspectRatio), cropScale.isFinite, (0.25...1).contains(cropScale),
              horizontal.isFinite, vertical.isFinite, (-100...100).contains(horizontal), (-100...100).contains(vertical) else {
            throw StraighteningError.invalidGeometry
        }
    }
    public func cropRect(in size: CGSize) -> CGRect {
        let ratio = aspectRatio == 0 ? size.width / size.height : aspectRatio
        let width = max(2, floor(min(size.width, size.height * ratio) * cropScale))
        let height = max(2, floor(min(size.height, size.width / ratio) * cropScale))
        let x = floor((size.width - width) * (horizontal / 100 + 1) / 2)
        let y = floor((size.height - height) * (vertical / 100 + 1) / 2)
        return CGRect(x: max(0, x), y: max(0, y), width: min(width, size.width), height: min(height, size.height))
    }
}

extension ColorPipeline {
    public static func geometrySize(width: Int, height: Int, edits: MediaEdits) throws -> CGSize {
        try edits.geometry.validate()
        let swapped = edits.geometry.quarterTurns % 2 != 0
        let plan = try StraighteningPlan(width: swapped ? height : width, height: swapped ? width : height,
                                        rotationRadians: edits.degrees * .pi / 180)
        return edits.geometry.cropRect(in: CGSize(width: plan.outputWidth, height: plan.outputHeight)).size
    }
    public static func geometry(_ image: CIImage, edits: MediaEdits) throws -> CIImage {
        let g = edits.geometry
        try g.validate()
        var input = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
        let w = input.extent.width, h = input.extent.height
        switch g.quarterTurns {
        case 1: input = input.transformed(by: .init(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
        case 2: input = input.transformed(by: .init(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
        case 3: input = input.transformed(by: .init(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
        default: break
        }
        if g.mirrored { input = input.transformed(by: .init(a: -1, b: 0, c: 0, d: 1, tx: input.extent.width, ty: 0)) }
        let straight = try geometry(input, degrees: edits.degrees)
        let rect = g.cropRect(in: straight.extent.size)
        return straight.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
    }
}

import CoreGraphics
import CoreImage
import Foundation

/// One decoded, upright preview per document. The actor serializes GPU work;
/// callers should coalesce pending angles rather than enqueue every slider tick.
public actor ImagePreviewSession {
    private let image: CIImage
    private let width: Int
    private let height: Int
    private let context: CIContext
    private var original: CGImage?

    public init(url: URL, maximumDimension: Int = 1600) throws {
        guard (2...8192).contains(maximumDimension) else { throw StraighteningError.invalidGeometry }
        let source = try ImageStraightener.source(url)
        let decoded = try ImageStraightener.thumbnail(source, maximumDimension: maximumDimension)
        image = CIImage(cgImage: decoded)
        width = decoded.width
        height = decoded.height
        context = ImageStraightener.makeContext()
    }

    public func render(degrees: Double) throws -> CGImage {
        try Task.checkCancellation()
        if degrees == 0, let original { return original }
        let plan = try StraighteningPlan(width: width, height: height, rotationRadians: degrees * .pi / 180)
        let rendered = try ImageStraightener.render(image, plan: plan, context: context)
        try Task.checkCancellation()
        if degrees == 0 { original = rendered }
        return rendered
    }
}

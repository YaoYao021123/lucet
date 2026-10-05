import CoreImage
import Foundation

public struct PreviewHistogram: Sendable {
    public let channels: [[Double]]
    /// Display statistics, always from an SDR rendition; not camera RAW/HDR clipping.
    public static func analyze(_ image: CIImage, headroom: Float = 1) -> Self {
        let extent = image.extent
        let scale = min(1, 256 / max(extent.width, extent.height))
        let small = ColorPipeline.toneMap(image, sourceHeadroom: headroom)
            .transformed(by: .init(translationX: -extent.minX, y: -extent.minY)).transformed(by: .init(scaleX: scale, y: scale))
        let width = max(1, Int(small.extent.width.rounded())), height = max(1, Int(small.extent.height.rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes {
            ColorPipeline.context().render(small, toBitmap: $0.baseAddress!, rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: ColorPipeline.outputSpace)
        }
        var channels = [[Double]](repeating: [Double](repeating: 0, count: 64), count: 3)
        for pixel in stride(from: 0, to: bytes.count, by: 4) where bytes[pixel + 3] > 0 {
            for channel in 0..<3 { channels[channel][Int(bytes[pixel + channel]) / 4] += 1 }
        }
        let peak = max(1, channels.flatMap { $0 }.max() ?? 1)
        return Self(channels: channels.map { $0.map { $0 / peak } })
    }
}

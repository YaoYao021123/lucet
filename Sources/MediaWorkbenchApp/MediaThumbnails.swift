import AVFoundation
import CoreGraphics
import CoreImage
import MediaCore

/// Small, ungraded source thumbnails. Decoded once per open, never while scrubbing.
enum MediaThumbnails {
    static func video(_ url: URL, duration: Double, count: Int = 12) async throws -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 140)
        generator.dynamicRangePolicy = .forceSDR
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        var images: [CGImage] = []
        // Serial async decoding bounds memory and leaves playback/export resources free.
        for index in 0..<count {
            try Task.checkCancellation()
            let seconds = max(0, duration - 0.05) * Double(index) / Double(max(1, count - 1))
            let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            images.append(result.image)
        }
        return images
    }

    static func image(_ frame: GradeFrame) throws -> CGImage {
        let scale = min(1, 320 / max(frame.original.extent.width, frame.original.extent.height))
        return try ColorPipeline.sdrBitmap(frame.original.transformed(by: .init(scaleX: scale, y: scale)),
                                           headroom: frame.sourceHeadroom)
    }
}

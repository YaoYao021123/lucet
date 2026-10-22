import AVFoundation
import CoreGraphics
import Foundation
import Vision

/// One frame offered as a Live Photo cover.
public struct CoverCandidate: Identifiable, @unchecked Sendable {
    public let id: Int
    /// Seconds in the source movie.
    public let time: Double
    public let image: CGImage
    /// 0…1 among this clip's frames: how crisp the frame is relative to the crispest.
    public let sharpness: Double
    /// Vision's capture quality of the least flattering face (blinks and blur lower it); nil without faces.
    public let faceQuality: Double?
    public let score: Double
}

/// Suggests the best cover for a Live Photo: the frame that is sharpest and, where there are people,
/// flatters them most. Beginners shouldn't have to scrub for it.
public enum CoverPicker {
    public static func candidates(in url: URL, range: ClosedRange<Double>, count: Int = 9) async throws -> (frames: [CoverCandidate], best: Int) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 420, height: 420)
        generator.dynamicRangePolicy = .forceSDR
        let tolerance = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        // Keep clear of the very first and last frames, where motion blur and cuts sit.
        let span = range.upperBound - range.lowerBound
        let margin = min(0.1, span * 0.04)
        let count = max(2, count)
        var raw: [(time: Double, image: CGImage, sharp: Double, face: Double?)] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let time = range.lowerBound + margin + (span - 2 * margin) * Double(index) / Double(count - 1)
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            raw.append((time, image, sharpness(of: image), faceQuality(of: image)))
        }
        let sharpest = max(1e-9, raw.map(\.sharp).max() ?? 1)
        let frames = raw.enumerated().map { index, item -> CoverCandidate in
            let s = item.sharp / sharpest
            let score = item.face.map { 0.55 * s + 0.45 * $0 } ?? s
            return CoverCandidate(id: index, time: item.time, image: item.image, sharpness: s, faceQuality: item.face, score: score)
        }
        return (frames, frames.max { $0.score < $1.score }?.id ?? 0)
    }

    /// Variance of a Laplacian on a small greyscale copy: high for crisp detail, near zero for blur.
    static func sharpness(of image: CGImage) -> Double {
        let width = 160, height = max(8, Int((160.0 * Double(image.height) / Double(max(1, image.width))).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0.0, squares = 0.0, n = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let laplacian = 4 * Double(pixels[i]) - Double(pixels[i - 1]) - Double(pixels[i + 1]) - Double(pixels[i - width]) - Double(pixels[i + width])
                sum += laplacian; squares += laplacian * laplacian; n += 1
            }
        }
        let mean = sum / max(1, n)
        return squares / max(1, n) - mean * mean
    }

    /// The lowest face capture quality in the frame, or nil when there are no faces.
    static func faceQuality(of image: CGImage) -> Double? {
        let request = VNDetectFaceCaptureQualityRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
              let faces = request.results, !faces.isEmpty else { return nil }
        return faces.compactMap { $0.faceCaptureQuality.map(Double.init) }.min()
    }
}

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import MediaCore
import UniformTypeIdentifiers

@main
struct MediaBenchmark {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic-12mp.jpg")
        let canvas = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 16000,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for row in 0..<30 {
            canvas.setFillColor(CGColor(red: CGFloat(row) / 40, green: 0.5, blue: 0.6, alpha: 1))
            canvas.fill(CGRect(x: 0, y: row * 100, width: 4000, height: 100))
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, canvas.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StraighteningError.renderFailed }
        let clock = ContinuousClock()
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        func summary(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            return ["median_ms": sorted[sorted.count / 2], "p95_ms": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1],
                    "max_ms": sorted.last!]
        }
        func consume(_ image: CGImage) throws {
            guard let data = image.dataProvider?.data, CFDataGetLength(data) > 0 else { throw StraighteningError.renderFailed }
        }
        // Warm the system/GPU before comparing equal sequences in one process.
        try consume(ImageStraightener.preview(url, degrees: 1))
        let start = clock.now
        let session = try ImagePreviewSession(url: url)
        try consume(await session.render(degrees: 0))
        let loadMS = milliseconds(start.duration(to: clock.now))
        var legacy: [Double] = [], cached: [Double] = []
        for index in 0..<40 {
            let angle = Double(index % 20 - 10) * 0.45
            let before = clock.now
            try consume(ImageStraightener.preview(url, degrees: angle))
            legacy.append(milliseconds(before.duration(to: clock.now)))
            let warm = clock.now
            try consume(await session.render(degrees: angle))
            cached.append(milliseconds(warm.duration(to: clock.now)))
        }
        let gradeLoadStart = clock.now
        let grading = try ImageGradeSession(url: url)
        let gradeContext = ColorPipeline.context()
        func materializeGrade(_ angle: Double) async throws {
            let frame = try await grading.frame(edits: MediaEdits(degrees: angle, lut: .warm, strength: 0.7))
            guard let bitmap = gradeContext.createCGImage(frame.image, from: frame.image.extent,
                format: .RGBAh, colorSpace: ColorPipeline.linearSpace) else { throw StraighteningError.renderFailed }
            try consume(bitmap)
        }
        try await materializeGrade(1)
        let gradingLoadMS = milliseconds(gradeLoadStart.duration(to: clock.now))
        var graded: [Double] = []
        for index in 0..<40 {
            let start = clock.now
            try await materializeGrade(Double(index % 20 - 10) * 0.45)
            graded.append(milliseconds(start.duration(to: clock.now)))
        }
        let result: [String: Any] = [
            "fixture": "synthetic 4000x3000 JPEG; 1600px preview; 40 interleaved angles",
            "scope": "decode/render + materialized pixels, excludes SwiftUI/display latency",
            "cached_load_ms": loadMS, "legacy": summary(legacy), "cached": summary(cached),
            "floating_grade_load_ms": gradingLoadMS, "floating_grade": summary(graded),
            "floating_grade_scope": "current image engine, 1600px float bitmap + warm 17^3 LUT at 70% + rotation; CPU-visible RGBAh result; excludes Metal drawable/presentation and HDR source decoding",
            "removed_ui_delay_ms": 120,
            "median_speedup": summary(legacy)["median_ms"]! / summary(cached)["median_ms"]!
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}

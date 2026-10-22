import AVFoundation
import CoreImage
import Foundation
import Testing
@testable import MediaCore

struct LiveEffectsTests {
    /// Writes a clip whose pixel at (x, y) in frame k is `value(x, y, k)`.
    private func makeMovie(_ url: URL, width: Int, height: Int, frames: Int, value: (Int, Int, Int) -> UInt8) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for k in 0..<frames {
            var buffer: CVPixelBuffer?
            _ = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<height {
                for x in 0..<width {
                    let v = value(x, y, k)
                    base[y * row + x * 4] = v; base[y * row + x * 4 + 1] = v; base[y * row + x * 4 + 2] = v; base[y * row + x * 4 + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            var attempts = 0
            while !input.isReadyForMoreMediaData && attempts < 800 { try await Task.sleep(for: .milliseconds(10)); attempts += 1 }
            try #require(adapter.append(pixels, withPresentationTime: CMTime(value: Int64(k), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }

    private func temp(_ ext: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext) }

    private func prepared(_ url: URL, seconds: Double) async throws -> PreparedVideo {
        try await VideoPipeline.prepare(url, clip: ClipSettings(start: 0, end: seconds, cover: 0.2), edits: MediaEdits(), sdr: true)
    }

    private func texture(_ x: Int, _ y: Int) -> UInt8 {
        let bx = (x + 100_000) / 6, by = (y + 100_000) / 6
        var h = UInt32(truncatingIfNeeded: bx &* 73856093 ^ by &* 19349663)
        h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
        return UInt8(40 + h % 180)
    }

    @Test func aligningUndoesHandShake() async throws {
        let url = temp("mov"); defer { try? FileManager.default.removeItem(at: url) }
        // The picture slides 3 px to the right every frame, as if the camera were drifting left.
        try await makeMovie(url, width: 320, height: 180, frames: 10) { x, y, k in texture(x - 3 * k, y) }
        let clip = try await prepared(url, seconds: 10.0 / 30)
        let blurred = try await LiveEffects.averagedFrame(of: clip, align: false)
        let steady = try await LiveEffects.averagedFrame(of: clip, align: true)
        let sharpBlurred = CoverPicker.sharpness(of: blurred), sharpSteady = CoverPicker.sharpness(of: steady)
        #expect(sharpSteady > sharpBlurred * 2.5, "aligned \(sharpSteady) vs plain \(sharpBlurred)")
    }

    @Test func aStillSceneKeepsItsBrightness() async throws {
        let url = temp("mov"); defer { try? FileManager.default.removeItem(at: url) }
        try await makeMovie(url, width: 128, height: 72, frames: 12) { _, _, _ in 110 }
        let image = try await LiveEffects.averagedFrame(of: try await prepared(url, seconds: 12.0 / 30), align: true)
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: ColorPipeline.outputSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        #expect(abs(Int(data[0]) - 110) <= 6, "got \(data[0])")
    }

    @Test func longExposureWritesAPhotoWithTheOriginalsDetails() async throws {
        let url = temp("mov"), photo = temp("jpg"); defer { for u in [url, photo] { try? FileManager.default.removeItem(at: u) } }
        try await makeMovie(url, width: 128, height: 72, frames: 12) { x, y, k in texture(x, y) }
        var options = ImageExportOptions(); options.format = .jpeg
        try await LiveEffects.longExposure(movie: url, clip: ClipSettings(start: 0, end: 12.0 / 30, cover: 0.2), edits: MediaEdits(),
                                           metadataSource: nil, options: options, to: photo)
        let source = try #require(CGImageSourceCreateWithURL(photo as CFURL, nil))
        let p = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 128 && p[kCGImagePropertyPixelHeight] as? Int == 72)
    }

    @Test func bounceAndLoopHaveTheRightLengths() async throws {
        let url = temp("mov"), bounce = temp("mov"), loop = temp("mov")
        defer { for u in [url, bounce, loop] { try? FileManager.default.removeItem(at: u) } }
        try await makeMovie(url, width: 96, height: 54, frames: 30) { x, y, k in UInt8(20 + k * 7) }
        let clip = ClipSettings(start: 0, end: 1, cover: 0.5)
        try await LiveEffects.repeating(.bounce, movie: url, clip: clip, edits: MediaEdits(), to: bounce)
        try await LiveEffects.repeating(.loop, movie: url, clip: clip, edits: MediaEdits(), to: loop)
        let bounceSeconds = try await AVURLAsset(url: bounce).load(.duration).seconds
        let loopSeconds = try await AVURLAsset(url: loop).load(.duration).seconds
        #expect(abs(bounceSeconds - 58.0 / 30) < 0.12, "bounce \(bounceSeconds)")      // 30 forward + 28 back
        #expect(abs(loopSeconds - 20.0 / 30) < 0.12, "loop \(loopSeconds)")            // 30 frames − 10 overlap
    }

    @Test func longClipsAreRefusedWithAMessage() {
        #expect(throws: Never.self) { try LiveEffects.checkLength(15) }
        #expect(throws: (any Error).self) { try LiveEffects.checkLength(15.5) }
    }
}

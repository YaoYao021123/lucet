import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaCore

struct LiveKeyPhotoTests {
    /// A one-second movie of the given shape (a grey ramp, so grading has something to act on).
    private func makeMovie(_ url: URL, width: Int, height: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            var buffer: CVPixelBuffer?
            _ = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels)!, 110, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            var attempts = 0
            while !input.isReadyForMoreMediaData && attempts < 500 { try await Task.sleep(for: .milliseconds(10)); attempts += 1 }
            try #require(adapter.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }

    /// A still with a capture date, camera and GPS, like a phone's.
    private func makeStill(_ url: URL, width: Int, height: Int) throws {
        let pixels = [UInt8](repeating: 120, count: width * height * 4)
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 16 Pro"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:05:01 18:30:00"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 121.5, kCGImagePropertyGPSLongitudeRef: "E"]
        ] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func originalPhotoBecomesTheKeyPhotoWithItsDateAndPlace() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("m.mov"), still = dir.appendingPathComponent("s.jpg")
        try await makeMovie(movie, width: 96, height: 128)
        try makeStill(still, width: 300, height: 400)   // same 3:4 shape, 3× the pixels
        var edits = MediaEdits(); edits.adjustments.exposure = 0.3
        let clip = ClipSettings(start: 0, end: 1, cover: 0.5)

        let kept = try await LivePhotoPipeline.export(movie, to: dir.appendingPathComponent("kept"), clip: clip, edits: edits,
                                                      keyPhoto: still, removeLocation: false)
        let p = try properties(kept.imageURL)
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 300 && p[kCGImagePropertyPixelHeight] as? Int == 400)
        let exif = try #require(p[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:05:01 18:30:00")
        #expect(p[kCGImagePropertyGPSDictionary] != nil)
        let maker = try #require(p[kCGImagePropertyMakerAppleDictionary] as? [String: Any])
        #expect(maker["17"] as? String == kept.identifier)

        // Sharing: location off, the rest stays.
        let shared = try await LivePhotoPipeline.export(movie, to: dir.appendingPathComponent("shared"), clip: clip, edits: edits,
                                                        keyPhoto: still, removeLocation: true)
        let q = try properties(shared.imageURL)
        #expect(q[kCGImagePropertyGPSDictionary] == nil && q[kCGImagePropertyExifDictionary] != nil)
    }

    @Test func aStillOfAnotherShapeFallsBackToAVideoFrame() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("m.mov"), still = dir.appendingPathComponent("s.jpg")
        try await makeMovie(movie, width: 96, height: 128)
        try makeStill(still, width: 400, height: 300)   // 4:3 landscape against a 3:4 movie
        let live = try await LivePhotoPipeline.export(movie, to: dir.appendingPathComponent("out"), clip: ClipSettings(start: 0, end: 1, cover: 0.5),
                                                      edits: MediaEdits(), keyPhoto: still, removeLocation: false)
        let p = try properties(live.imageURL)
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 96 && p[kCGImagePropertyPixelHeight] as? Int == 128)
        #expect(p[kCGImagePropertyGPSDictionary] == nil)
    }
}

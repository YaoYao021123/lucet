import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import MediaCore

@MainActor
struct MediaInspectorTests {
    @Test func testReadsVideoTransformDurationAndColorMetadata() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 32,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 32, ty: 0)
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        try #require(writer.startWriting(), "Writer could not start")
        writer.startSession(atSourceTime: .zero)
        for index in 0..<4 {
            var buffer: CVPixelBuffer?
            #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 32, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels)!, 0, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            var attempts = 0
            while !input.isReadyForMoreMediaData && attempts < 500 && writer.status == .writing {
                try await Task.sleep(for: .milliseconds(10))
                attempts += 1
            }
            try #require(input.isReadyForMoreMediaData)
            try #require(adapter.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
        let metadata = try await MediaInspector.inspect(url)
        #expect(metadata.kind == .video)
        #expect(metadata.pixelWidth == 64)
        #expect(metadata.pixelHeight == 32)
        #expect(metadata.displayWidth == 32)
        #expect(metadata.displayHeight == 64)
        #expect(metadata.hasAudio == false)
        #expect(abs(try #require(metadata.durationSeconds) - 4.0 / 30.0) < 0.01)
        #expect(metadata.colorPrimaries == AVVideoColorPrimaries_ITU_R_709_2)
        #expect(metadata.transferFunction == AVVideoTransferFunction_ITU_R_709_2)
    }

    @Test func testReadsImageHeaderAndRespectsPortraitOrientation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let pixels: [UInt8] = Array(repeating: 120, count: 3 * 2 * 4)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        let metadata = try await MediaInspector.inspect(url)
        #expect(metadata.kind == .image)
        #expect(metadata.pixelWidth == 3)
        #expect(metadata.pixelHeight == 2)
        #expect(metadata.displayWidth == 2)
        #expect(metadata.displayHeight == 3)
        #expect(metadata.orientation == 6)
        #expect(metadata.format == UTType.jpeg.identifier)
        #expect(metadata.durationSeconds == nil)
    }

    @Test func testRejectsMissingFilesAndDirectories() async throws {
        for url in [FileManager.default.temporaryDirectory,
                    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)] {
            do {
                _ = try await MediaInspector.inspect(url)
                Issue.record("Expected unreadable path")
            } catch MediaInspectionError.unreadable { }
        }
    }
}

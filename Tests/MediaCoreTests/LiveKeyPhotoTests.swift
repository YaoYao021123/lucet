import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaCore

struct LiveKeyPhotoTests {
    /// A one-second movie of the given shape (a grey ramp, so grading has something to act on).
    private func makeMovie(_ url: URL, width: Int, height: Int, metadata: [AVMetadataItem] = []) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = metadata
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

    /// An iPhone-style HDR still: a gain map lifts the bottom half to four times SDR white.
    private func makeHDRStill(_ url: URL, width: Int, height: Int) throws {
        let linear = ColorPipeline.linearSpace
        let dim = CIImage(color: CIColor(red: 0.18, green: 0.2, blue: 0.22, colorSpace: linear)!).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let bright = CIImage(color: CIColor(red: 4, green: 3.8, blue: 3.5, colorSpace: linear)!).cropped(to: CGRect(x: 0, y: 0, width: width, height: height / 2))
        let hdr = bright.composited(over: dim)
        let data = try #require(HDRGain.encode(base: ColorPipeline.toneMap(hdr, sourceHeadroom: 4), hdr: hdr, format: .jpeg, quality: 0.95))
        try data.write(to: url)
    }

    private func gainMaps(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap]
            .filter { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }.count
    }

    @Test func anHDRKeyPhotoKeepsItsGainMap() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("m.mov"), still = dir.appendingPathComponent("s.jpg")
        try await makeMovie(movie, width: 96, height: 128)
        try makeHDRStill(still, width: 300, height: 400)
        #expect(try ImageGradeSession.decode(still).contentHeadroom > 2, "test still should decode as HDR")
        let clip = ClipSettings(start: 0, end: 1, cover: 0.5)

        let kept = try await LivePhotoPipeline.export(movie, to: dir.appendingPathComponent("hdr"), clip: clip, edits: MediaEdits(),
                                                      keyPhoto: still, removeLocation: false)
        #expect(gainMaps(kept.imageURL) > 0)
        #expect(try ImageGradeSession.decode(kept.imageURL).contentHeadroom > 2)
        let maker = try #require(try properties(kept.imageURL)[kCGImagePropertyMakerAppleDictionary] as? [String: Any])
        #expect(maker["17"] as? String == kept.identifier, "the HDR still is still paired with its motion")

        let plain = try await LivePhotoPipeline.export(movie, to: dir.appendingPathComponent("sdr"), clip: clip, edits: MediaEdits(),
                                                       keyPhoto: still, removeLocation: false, keepHDR: false)
        #expect(gainMaps(plain.imageURL) == 0)
    }

    private func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier; item.value = value as NSString; item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    @Test func aLiveCutFromAClipCarriesWhenAndWhereItWasShot() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("clip.mov")
        try await makeMovie(movie, width: 128, height: 96, metadata: [
            item(.quickTimeMetadataCreationDate, "2026-10-07T09:15:00+0800"),
            item(.quickTimeMetadataLocationISO6709, "+22.48617+113.91070+012.000/"),
            item(.quickTimeMetadataMake, "DJI"), item(.quickTimeMetadataModel, "Mini 4 Pro")])
        let capture = await CaptureMetadata.read(movie)
        let shot = try #require(capture.date)
        #expect(capture.location == "+22.48617+113.91070+012.000/" && capture.model == "Mini 4 Pro")

        let clip = ClipSettings(start: 0, end: 1, cover: 0.5)
        let live = try await LivePhotoPipeline.export(movie, to: dir.appendingPathComponent("kept"), clip: clip, edits: MediaEdits(),
                                                      removeLocation: false)
        let p = try properties(live.imageURL)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let exif = try #require(p[kCGImagePropertyExifDictionary] as? [CFString: Any])
        // Dated at the cover's moment in the clip.
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == formatter.string(from: shot.addingTimeInterval(live.coverSeconds)))
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String == "Mini 4 Pro")
        let gps = try #require(p[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        #expect(abs((gps[kCGImagePropertyGPSLatitude] as? Double ?? 0) - 22.48617) < 1e-4 && gps[kCGImagePropertyGPSLongitudeRef] as? String == "E")
        let motion = await CaptureMetadata.read(live.videoURL)
        #expect(motion.date.map { abs($0.timeIntervalSince(shot) - live.coverSeconds) < 1.01 } == true)
        #expect(motion.location != nil && motion.model == "Mini 4 Pro")

        // Remove location: the date and camera stay, the place goes from both halves.
        let shared = try await LivePhotoPipeline.export(movie, to: dir.appendingPathComponent("shared"), clip: clip, edits: MediaEdits(),
                                                        removeLocation: true)
        let q = try properties(shared.imageURL)
        #expect(q[kCGImagePropertyGPSDictionary] == nil && q[kCGImagePropertyExifDictionary] != nil)
        let sharedMotion = await CaptureMetadata.read(shared.videoURL)
        #expect(sharedMotion.location == nil && sharedMotion.date != nil)
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

struct CoverPickerTests {
    /// 30 frames of flat grey, except frames 12–17, which carry crisp detail.
    private func makeMovie(_ url: URL) async throws {
        let width = 160, height = 120
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
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<height {
                for x in 0..<width {
                    let crisp = (12...17).contains(index) && ((x / 4 + y / 4) % 2 == 0)
                    let value: UInt8 = (12...17).contains(index) ? (crisp ? 235 : 20) : 120
                    for c in 0..<3 { base[y * row + x * 4 + c] = value }
                    base[y * row + x * 4 + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            var attempts = 0
            while !input.isReadyForMoreMediaData && attempts < 500 { try await Task.sleep(for: .milliseconds(10)); attempts += 1 }
            try #require(adapter.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }

    @Test func suggestsTheCrispestFrameAndNeverScoresFacesOnEmptyScenes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeMovie(url)
        let (frames, best) = try await CoverPicker.candidates(in: url, range: 0...1, count: 9)
        #expect(frames.count == 9)
        #expect(frames.map(\.time) == frames.map(\.time).sorted())
        #expect((0.38...0.62).contains(frames[best].time), "best frame at \(frames[best].time)")
        #expect(frames[best].sharpness > 0.99 && frames[0].sharpness < 0.2)
        #expect(frames.allSatisfy { $0.faceQuality == nil })
    }
}

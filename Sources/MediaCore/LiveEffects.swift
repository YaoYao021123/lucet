import AVFoundation
import CoreImage
import Foundation
import Vision

/// Things a short clip (a Live Photo's motion) can become besides a Live Photo: one long-exposure
/// photograph, or a video that loops or bounces. All of them use the clip exactly as edited —
/// trim, speed, crop and colour — by reading frames from the same composition the preview plays.
public enum LiveEffects {

    // MARK: Long exposure

    /// Averages every frame of the clip into one photograph (silky water, melting crowds). With `align`, each
    /// frame is first shifted back onto the first one, so a hand-held clip doesn't just blur.
    public static func longExposure(movie: URL, clip: ClipSettings, edits: MediaEdits, metadataSource: URL?,
                                    options: ImageExportOptions, align: Bool = true, to output: URL,
                                    progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard output.isFileURL, !FileManager.default.fileExists(atPath: output.path) else { throw VideoWorkError.outputExists }
        var silent = clip
        silent.originalVolume = 0; silent.musicURL = nil
        let prepared = try await VideoPipeline.prepare(movie, clip: silent, edits: edits, sdr: true)
        let image = try await averagedFrame(of: prepared, align: align, progress: progress)
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if options.keepMetadata, let source = metadataSource {
            properties.merge(ImageExporter.metadata(of: source, removeLocation: options.removeLocation,
                                                    width: image.width, height: image.height)) { _, new in new }
        }
        if options.format.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.1, options.quality)) }
        let rendered = ImageExporter.Rendered(bitmap: image, properties: properties, format: options.format, hdrData: nil)
        try ImageExporter.write(rendered, to: output, source: metadataSource ?? movie)
        progress?(1)
    }

    static func averagedFrame(of prepared: PreparedVideo, align: Bool,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws -> CGImage {
        let reader = try AVAssetReader(asset: prepared.asset)
        let tracks = try await prepared.asset.loadTracks(withMediaType: .video)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        if let composition = prepared.videoComposition { output.videoComposition = composition }
        else { output.videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: prepared.asset) }
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoWorkError.failed(L("无法读取视频画面。")) }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? VideoWorkError.failed(L("无法读取视频画面。")) }
        let total = max(1, prepared.duration * 30)
        var accumulator: FrameAccumulator?
        var reference: CGImage?
        var index = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            if accumulator == nil { accumulator = FrameAccumulator(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)) }
            var shift = (0, 0)
            if align {
                let small = smallImage(buffer)
                if let reference, let small, let found = translation(of: small, to: reference) {
                    let scale = Double(CVPixelBufferGetWidth(buffer)) / Double(small.width)
                    shift = (Int((Double(found.0) * scale).rounded()), Int((Double(found.1) * scale).rounded()))
                } else if reference == nil { reference = small }
            }
            accumulator?.add(buffer, shiftX: shift.0, shiftY: shift.1)
            index += 1
            progress?(min(0.95, Double(index) / total))
        }
        if reader.status == .failed { throw reader.error ?? VideoWorkError.failed(L("读取视频画面时出错。")) }
        guard let result = accumulator?.image() else { throw VideoWorkError.failed(L("片段里没有可用的画面。")) }
        return result
    }

    /// A ~320 px copy of a frame, used only to find how far the camera moved.
    static func smallImage(_ buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        let scale = 320 / max(image.extent.width, image.extent.height)
        let scaled = image.transformed(by: .init(scaleX: scale, y: scale))
        return ColorPipeline.shared.createCGImage(scaled, from: scaled.extent.integral)
    }

    /// How far `image` must move, in pixels of the (small) picture, to land on `reference`. Large jumps are
    /// ignored: they're a scene change, not hand shake, and shifting by them would only smear the result.
    static func translation(of image: CGImage, to reference: CGImage) -> (Int, Int)? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: image)
        guard (try? VNSequenceRequestHandler().perform([request], on: reference)) != nil,
              let result = request.results?.first as? VNImageTranslationAlignmentObservation else { return nil }
        let t = result.alignmentTransform
        guard abs(t.tx) < Double(image.width) * 0.15, abs(t.ty) < Double(image.height) * 0.15 else { return nil }
        // Vision measures y upwards; pixel rows run downwards.
        return (Int(t.tx.rounded()), Int((-t.ty).rounded()))
    }

    /// Sums frames in linear light (averaging the encoded values would make the result too dark).
    final class FrameAccumulator {
        let width: Int, height: Int
        private var sum: [Float]
        private var count = 0
        private static let linear: [Float] = (0..<256).map { v in
            let c = Float(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        init(width: Int, height: Int) {
            self.width = width; self.height = height
            sum = [Float](repeating: 0, count: width * height * 3)
        }

        /// Adds a BGRA frame moved by (shiftX, shiftY) pixels; pixels that move in from outside copy the edge.
        func add(_ buffer: CVPixelBuffer, shiftX: Int, shiftY: Int) {
            guard CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height else { return }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let lut = Self.linear
            let w = width, h = height
            sum.withUnsafeMutableBufferPointer { out in
                for y in 0..<h {
                    let sy = min(h - 1, max(0, y - shiftY))
                    let row = base + sy * stride
                    var o = y * w * 3
                    for x in 0..<w {
                        let p = row + min(w - 1, max(0, x - shiftX)) * 4
                        out[o] += lut[Int(p[2])]; out[o + 1] += lut[Int(p[1])]; out[o + 2] += lut[Int(p[0])]
                        o += 3
                    }
                }
            }
            count += 1
        }

        func image() -> CGImage? {
            guard count > 0 else { return nil }
            let scale = 1 / Float(count)
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            for i in 0..<(width * height) {
                for c in 0..<3 {
                    let v = min(1, max(0, sum[i * 3 + c] * scale))
                    let encoded = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
                    pixels[i * 4 + c] = UInt8(min(255, max(0, (encoded * 255).rounded())))
                }
            }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: ColorPipeline.outputSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    // MARK: Loop and bounce

    public enum Repeat: Sendable { case loop, bounce }

    /// A video that repeats without a visible jump: `.loop` fades the end into the start; `.bounce` plays forward
    /// and then backward. Silent, because sound doesn't loop or reverse well.
    public static func repeating(_ kind: Repeat, movie: URL, clip: ClipSettings, edits: MediaEdits, to output: URL,
                                 progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard output.isFileURL, !FileManager.default.fileExists(atPath: output.path) else { throw VideoWorkError.outputExists }
        var silent = clip
        silent.originalVolume = 0; silent.musicURL = nil
        let prepared = try await VideoPipeline.prepare(movie, clip: silent, edits: edits, sdr: true)
        let track = try await prepared.asset.loadTracks(withMediaType: .video).first
        let nominal = try await track?.load(.nominalFrameRate) ?? 30
        let fps = nominal > 1 ? Double(nominal) : 30
        let frameCount = max(4, Int((prepared.duration * fps).rounded(.down)))
        let times = (0..<frameCount).map { Double($0) / fps }

        let generator = AVAssetImageGenerator(asset: prepared.asset)
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = prepared.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        func frame(_ index: Int) async throws -> CGImage {
            try await generator.image(at: CMTime(seconds: times[index], preferredTimescale: 60000)).image
        }

        // The sequence of source frames to write; a loop's overlap is blended while writing.
        enum Step { case plain(Int), blend(tail: Int, head: Int, amount: Double) }
        var steps: [Step] = []
        switch kind {
        case .bounce:
            steps = (0..<frameCount).map { .plain($0) } + (1..<(frameCount - 1)).reversed().map { .plain($0) }
        case .loop:
            let overlap = max(2, min(Int(fps * 0.5), frameCount / 3))
            let main = frameCount - overlap
            steps = (0..<overlap).map { k in .blend(tail: main + k, head: k, amount: Double(k + 1) / Double(overlap + 1)) }
                + (overlap..<main).map { .plain($0) }
        }

        let first = try await frame(0)
        let width = first.width, height = first.height
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".workbench-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(60_000_000, Double(width * height) * fps * 0.12)]])
        input.expectsMediaDataInRealTime = false
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoWorkError.failed(L("无法创建视频文件。")) }
        writer.startSession(atSourceTime: .zero)

        var cache: [Int: CGImage] = [0: first]
        // A frame from the small cache of early frames (the loop's blend and the bounce's turn reuse them).
        func cached(_ i: Int) async throws -> CGImage {
            if let hit = cache[i] { return hit }
            let image = try await frame(i)
            if i < 3 { cache[i] = image }
            return image
        }
        for (position, step) in steps.enumerated() {
            try Task.checkCancellation()
            let picture: CIImage
            switch step {
            case .plain(let i):
                picture = CIImage(cgImage: try await cached(i))
            case .blend(let tail, let head, let amount):
                let a = CIImage(cgImage: try await frame(tail)), b = CIImage(cgImage: try await cached(head))
                // The head fades in over the tail; `amount` rises from 0 to 1 across the overlap.
                picture = b.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: a, kCIInputTimeKey: 1 - amount])
            }
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
                attempts += 1
                if attempts > 4000 || writer.status == .failed { throw writer.error ?? VideoWorkError.failed(L("视频写入失败。")) }
            }
            guard let pool = adapter.pixelBufferPool else { throw VideoWorkError.failed(L("视频写入失败。")) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw VideoWorkError.failed(L("视频写入失败。")) }
            ColorPipeline.shared.render(picture, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: ColorPipeline.outputSpace)
            guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(position), timescale: CMTimeScale(fps.rounded()))) else {
                throw writer.error ?? VideoWorkError.failed(L("视频写入失败。"))
            }
            progress?(0.05 + 0.9 * Double(position + 1) / Double(steps.count))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoWorkError.failed(L("视频写入失败。")) }
        try FileManager.default.moveItem(at: temporary, to: output)
        progress?(1)
    }
}

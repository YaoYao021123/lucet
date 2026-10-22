import AVFoundation
import CoreImage
import Foundation
import VideoToolbox

private final class ExportSessionHandle: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

public enum VideoWorkError: Error, LocalizedError {
    case invalidRange, missingTrack, outputExists, failed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRange: L("片段起止时间或封面时间无效。")
        case .missingTrack: L("没有可用的视频或音频轨道。")
        case .outputExists: L("目标已存在，请选择新的文件名。")
        case .failed(let detail): L("媒体处理失败：\(detail)")
        }
    }
}

public struct ClipSettings: Sendable, Codable, Equatable {
    public var start: Double
    public var end: Double
    public var cover: Double
    public var originalVolume: Float
    public var musicURL: URL?
    public var musicVolume: Float
    public var speed: Double
    public init(start: Double, end: Double, cover: Double, originalVolume: Float = 1,
                musicURL: URL? = nil, musicVolume: Float = 0.5, speed: Double = 1) {
        self.start = start; self.end = end; self.cover = cover
        self.originalVolume = originalVolume; self.musicURL = musicURL; self.musicVolume = musicVolume
        self.speed = speed
    }
    public var sourceDuration: Double { end - start }
    public var outputDuration: Double { sourceDuration / speed }
    public var outputCover: Double { (cover - start) / speed }
    /// Move the selection as one unit, keeping its length and relative cover.
    public func shifted(by delta: Double, duration: Double) -> ClipSettings {
        guard delta.isFinite, duration.isFinite, start.isFinite, end.isFinite,
              sourceDuration > 0, duration >= sourceDuration else { return self }
        let actual = min(duration - end, max(-start, delta))
        var result = self
        result.start += actual; result.end += actual; result.cover += actual
        return result
    }
    public func validate(duration: Double, live: Bool = false) throws {
        guard duration.isFinite, start.isFinite, end.isFinite, cover.isFinite,
              start >= 0, end <= duration + 0.001, end - start >= 0.1,
              cover >= start, cover < end,
              originalVolume.isFinite, musicVolume.isFinite,
              (0...1).contains(originalVolume), (0...1).contains(musicVolume),
              speed.isFinite, (0.5...4).contains(speed),
              !live || (outputDuration >= 0.5 && outputDuration <= 3.001) else { throw VideoWorkError.invalidRange }
    }
}

public struct PreparedVideo {
    public let asset: AVMutableComposition
    public let videoComposition: AVVideoComposition?
    public let audioMix: AVAudioMix
    public let duration: Double
}

public enum VideoCodecChoice: String, Codable, CaseIterable, Sendable {
    case h264, hevc
    public var title: String { self == .h264 ? L("H.264（兼容）") : L("HEVC（更小）") }
    var preset: String { self == .h264 ? AVAssetExportPresetHighestQuality : AVAssetExportPresetHEVCHighestQuality }
}

/// AI HDR for the motion (experimental): gain maps worked out on frames a short step apart and blended in
/// between, so the glow follows the picture without flickering.
struct MotionGain: @unchecked Sendable {
    let start: Double
    let step: Double
    let maps: [CIImage]
    /// Long side the glow is worked out at; the gain map is smooth, so small is enough. Tests lower it.
    nonisolated(unsafe) static var size = 384

    /// The gain at a moment of the source movie.
    func at(_ seconds: Double) -> CIImage? {
        guard let first = maps.first else { return nil }
        guard maps.count > 1, step > 0 else { return first }
        let position = min(Double(maps.count - 1), max(0, (seconds - start) / step))
        let index = min(maps.count - 2, Int(position)), fraction = position - Double(index)
        return maps[index + 1].applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: maps[index], kCIInputTimeKey: 1 - fraction])
            .cropped(to: first.extent)
    }

    /// Gain maps every `step` seconds over a range of the source (a single map when the range is a moment).
    static func make(_ url: URL, from start: Double, to end: Double, step: Double) async -> MotionGain? {
        guard let model = AutoHDR.shared else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.dynamicRangePolicy = .forceSDR
        generator.maximumSize = CGSize(width: 512, height: 512)
        let tolerance = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceBefore = tolerance; generator.requestedTimeToleranceAfter = tolerance
        let count = end > start ? Int(((end - start) / step).rounded(.up)) + 1 : 1
        var frames: [CGImage] = []
        for index in 0..<count {
            guard !Task.isCancelled,
                  let frame = try? await generator.image(at: CMTime(seconds: min(end, start + Double(index) * step), preferredTimescale: 600)).image else { return nil }
            frames.append(frame)
        }
        let maps = model.gains(for: frames, size: size)
        return maps.isEmpty ? nil : MotionGain(start: start, step: step, maps: maps)
    }
}

public enum VideoPipeline {
    /// Previews and exports the same selected range, geometry, LUT and audio mix.
    public static func prepare(_ url: URL, clip: ClipSettings, edits: MediaEdits,
                               sdr: Bool, preview: VideoPreviewState? = nil) async throws -> PreparedVideo {
        let source = AVURLAsset(url: url)
        let duration = try await source.load(.duration).seconds
        try clip.validate(duration: duration)
        guard let sourceVideo = try await source.loadTracks(withMediaType: .video).first else { throw VideoWorkError.missingTrack }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoWorkError.missingTrack
        }
        // Some encoders open a file with a few milliseconds of nothing (an empty edit); a frame there has no
        // picture, so the range starts at the first real frame.
        let firstFrame = try await sourceVideo.load(.segments).first { !$0.isEmpty }?.timeMapping.target.start ?? .zero
        let end = CMTime(seconds: clip.end, preferredTimescale: 60000)
        let start = min(max(CMTime(seconds: clip.start, preferredTimescale: 60000), firstFrame), end - CMTime(seconds: 0.05, preferredTimescale: 60000))
        let range = CMTimeRange(start: start, end: end)
        try video.insertTimeRange(range, of: sourceVideo, at: .zero)
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        var mixInputs: [AVMutableAudioMixInputParameters] = []
        for sourceAudio in try await source.loadTracks(withMediaType: .audio) {
            guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            // Some audio tracks finish earlier than the video.
            let audioRange = try await sourceAudio.load(.timeRange)
            let intersection = CMTimeRangeGetIntersection(range, otherRange: audioRange)
            if intersection.duration.seconds > 0 {
                try audio.insertTimeRange(intersection, of: sourceAudio, at: intersection.start - range.start)
                let mix = AVMutableAudioMixInputParameters(track: audio)
                mix.setVolume(clip.originalVolume, at: .zero); mixInputs.append(mix)
            }
        }
        let outputDuration = CMTime(seconds: clip.outputDuration, preferredTimescale: 60000)
        if clip.speed != 1 {
            // Scale camera video and original sound together. Add music later so
            // the soundtrack retains its own tempo and fills the output duration.
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration), toDuration: outputDuration)
        }
        if let musicURL = clip.musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            guard let sourceMusic = try await musicAsset.loadTracks(withMediaType: .audio).first,
                  let music = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoWorkError.missingTrack
            }
            let available = try await sourceMusic.load(.timeRange)
            let length = min(available.duration.seconds, clip.outputDuration)
            guard length > 0 else { throw VideoWorkError.missingTrack }
            try music.insertTimeRange(CMTimeRange(start: available.start, duration: CMTime(seconds: length, preferredTimescale: 600)),
                                      of: sourceMusic, at: .zero)
            let mix = AVMutableAudioMixInputParameters(track: music)
            mix.setVolume(clip.musicVolume, at: .zero); mixInputs.append(mix)
        }
        let mix = AVMutableAudioMix(); mix.inputParameters = mixInputs
        let formats = try await sourceVideo.load(.formatDescriptions)
        let extensions = formats.first.flatMap { CMFormatDescriptionGetExtensions($0) as? [String: Any] }
        let transfer = extensions?[kCMFormatDescriptionExtension_TransferFunction as String] as? String
        let sourceIsHDR = transfer == AVVideoTransferFunction_ITU_R_2100_HLG || transfer == AVVideoTransferFunction_SMPTE_ST_2084_PQ
        var filtered: AVVideoComposition?
        // AI HDR on the motion: both HDR switches on, for an ordinary source. Exports work out the glow every
        // 0.1 s (at most 300 times); the preview uses the cover's for the whole clip.
        var motionGain: MotionGain?
        if edits.hdrEffect, edits.hdrAmount > 0, !sourceIsHDR {
            motionGain = preview == nil
                ? await MotionGain.make(url, from: clip.start, to: clip.end, step: max(0.1, (clip.end - clip.start) / 300))
                : await MotionGain.make(url, from: clip.cover, to: clip.cover, step: 1)
        }
        if sdr || edits.hasLUT || edits.hasAdjustments || edits.hasGeometry || edits.hdrEffect {
            let context = ColorPipeline.context()
            let natural = try await sourceVideo.load(.naturalSize)
            let size = CGRect(origin: .zero, size: natural).applying(video.preferredTransform).standardized.size
            let previewScale: CGFloat = preview.map { min(1, CGFloat($0.maximumDimension) / max(size.width, size.height)) } ?? 1
            let previewWidth = CGFloat(max(2, Int(size.width * previewScale) / 2 * 2))
            let previewHeight = CGFloat(max(2, Int(size.height * previewScale) / 2 * 2))
            let previewSize = CGSize(width: previewWidth, height: previewHeight)
            let value = try await AVMutableVideoComposition.videoComposition(with: composition, applyingCIFiltersWithHandler: { request in
                do {
                    let showOriginal = preview?.showsOriginal == true
                    let settings = showOriginal ? MediaEdits() : (preview?.snapshot() ?? edits)
                    // This path is deliberately SDR; the unfiltered AVPlayer path
                    // retains the source HDR transfer function for native playback.
                    // Rec.709 composition properties below ask AVFoundation to
                    // convert source frames. Never invent a PQ/HLG headroom or
                    // tone-map an already converted SDR frame a second time.
                    // An HLG composition gives SDR frames an HDR container's
                    // headroom metadata. It does not make those source pixels
                    // HDR; tone mapping that metadata would darken white twice.
                    // A moment with no frame (a gap in the file) arrives as an endless empty picture; give it the clip's size.
                    let picture = request.sourceImage.extent.isInfinite ? request.sourceImage.cropped(to: CGRect(origin: .zero, size: size)) : request.sourceImage
                    let source = settings.hdrEffect && !sourceIsHDR && !showOriginal ? picture
                        : ColorPipeline.toneMap(picture, sourceHeadroom: max(1, picture.contentHeadroom))
                    // Scale before grading: 4K source decoding is retained, but
                    // interactive LUT/HDR/geometry work uses a bounded canvas.
                    let small = preview == nil ? source : source.transformed(by: .init(scaleX: previewScale, y: previewScale))
                    let graded = try ColorPipeline.grade(small, edits: settings)
                    let expanded: CIImage
                    if settings.hdrEffect, settings.hdrAmount > 0, let motionGain,
                       let gain = motionGain.at(clip.start + request.compositionTime.seconds * clip.speed) {
                        expanded = ColorPipeline.applyHDR(graded, gain: gain, amount: settings.hdrAmount)
                    } else {
                        expanded = settings.hdrEffect ? try HDRExpansion.image(graded) : graded
                    }
                    var frame = try ColorPipeline.geometry(expanded, edits: settings)
                    if preview != nil {
                        // A stable canvas permits angle changes without replacing
                        // the player item. Letterbox rather than stretch the crop.
                        let scale = min(previewSize.width / frame.extent.width, previewSize.height / frame.extent.height)
                        frame = frame.transformed(by: .init(scaleX: scale, y: scale))
                        frame = frame.transformed(by: .init(translationX: (previewSize.width - frame.extent.width) / 2,
                                                           y: (previewSize.height - frame.extent.height) / 2))
                        frame = frame.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: previewSize)))
                    }
                    request.finish(with: frame, context: context)
                } catch { request.finish(with: error) }
            })
            let outputSize = try ColorPipeline.geometrySize(width: Int(size.width.rounded()), height: Int(size.height.rounded()), edits: edits)
            // H.264 export dimensions must be even. Crop, never rescale/stretch.
            value.renderSize = preview == nil
                ? CGSize(width: max(2, Int(outputSize.width) / 2 * 2), height: max(2, Int(outputSize.height) / 2 * 2)) : previewSize
            value.colorPrimaries = edits.hdrEffect ? AVVideoColorPrimaries_ITU_R_2020 : AVVideoColorPrimaries_ITU_R_709_2
            value.colorTransferFunction = edits.hdrEffect ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_ITU_R_709_2
            value.colorYCbCrMatrix = edits.hdrEffect ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2
            if clip.speed != 1 {
                let rate = try await sourceVideo.load(.nominalFrameRate)
                // Scaled track timestamps otherwise override frameDuration and
                // turn 60 fps at 2× into an unnecessary 120 fps output.
                value.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
                value.frameDuration = CMTime(seconds: 1 / min(60, max(1, Double(rate))), preferredTimescale: 60000)
            }
            filtered = value
        }
        return PreparedVideo(asset: composition, videoComposition: filtered, audioMix: mix, duration: clip.outputDuration)
    }

    public static func export(_ url: URL, to output: URL, clip: ClipSettings, edits: MediaEdits,
                              codec: VideoCodecChoice = .h264,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try Task.checkCancellation()
        guard output.isFileURL, !FileManager.default.fileExists(atPath: output.path) else { throw VideoWorkError.outputExists }
        let prepared = try await prepare(url, clip: clip, edits: edits, sdr: true)
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".workbench-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if edits.hdrEffect {
            try await exportHLG(prepared, to: temporary, progress: progress)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: output)
            progress?(1)
            return
        }
        guard let exporter = AVAssetExportSession(asset: prepared.asset, presetName: codec.preset) else {
            throw VideoWorkError.failed(L("无法创建编码器"))
        }
        exporter.videoComposition = prepared.videoComposition; exporter.audioMix = prepared.audioMix
        exporter.audioTimePitchAlgorithm = .spectral
        try Task.checkCancellation()
        let handle = ExportSessionHandle(exporter)
        let updates = progress.map { report in
            Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    report(min(0.99, Double(handle.session.progress)))
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                }
            }
        }
        defer { updates?.cancel() }
        try await withTaskCancellationHandler {
            try await exporter.export(to: temporary, as: .mov)
        } onCancel: { handle.session.cancelExport() }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: output)
        progress?(1)
    }

    /// Explicit 10-bit buffers and HEVC Main10 encoding; an HDR flag alone is insufficient.
    private static func exportHLG(_ prepared: PreparedVideo, to output: URL,
                                  progress: (@Sendable (Double) -> Void)?) async throws {
        guard let composition = prepared.videoComposition else { throw VideoWorkError.missingTrack }
        let reader = try AVAssetReader(asset: prepared.asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let videos = try await prepared.asset.loadTracks(withMediaType: .video)
        let readVideo = AVAssetReaderVideoCompositionOutput(videoTracks: videos, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        ])
        readVideo.videoComposition = composition; readVideo.alwaysCopiesSampleData = false
        let size = composition.renderSize
        let writeVideo = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020],
            AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                AVVideoAverageBitRateKey: max(4_000_000, Int(size.width * size.height * 6))]
        ])
        var channels: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(readVideo, writeVideo)]
        let audios = try await prepared.asset.loadTracks(withMediaType: .audio)
        if !audios.isEmpty {
            let readAudio = AVAssetReaderAudioMixOutput(audioTracks: audios, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false
            ])
            readAudio.audioMix = prepared.audioMix; readAudio.audioTimePitchAlgorithm = .spectral
            let writeAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000
            ])
            channels.append((readAudio, writeAudio))
        }
        for (read, write) in channels {
            guard reader.canAdd(read), writer.canAdd(write) else { throw VideoWorkError.failed(L("HDR 编码器不支持当前轨道")) }
            reader.add(read); writer.add(write)
        }
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? VideoWorkError.failed(L("HDR 编码未开始")) }
        writer.startSession(atSourceTime: .zero)
        do {
            var finished = Set<Int>()
            var reported = 0.0
            while finished.count < channels.count {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? VideoWorkError.failed(L("HDR 编码中断")) }
                var advanced = false
                for (index, channel) in channels.enumerated() where !finished.contains(index) && channel.1.isReadyForMoreMediaData {
                    if let sample = channel.0.copyNextSampleBuffer() {
                        guard channel.1.append(sample) else { throw writer.error ?? VideoWorkError.failed(L("HDR 样本写入失败")) }
                        if index == 0 {
                            let fraction = min(0.99, CMSampleBufferGetPresentationTimeStamp(sample).seconds / prepared.duration)
                            if fraction - reported >= 0.02 { progress?(fraction); reported = fraction }
                        }
                    } else { channel.1.markAsFinished(); finished.insert(index) }
                    advanced = true
                }
                if !advanced { try await Task.sleep(for: .milliseconds(2)) }
            }
            guard reader.status == .completed else { throw reader.error ?? VideoWorkError.failed(L("HDR 读取未完成")) }
            writer.endSession(atSourceTime: CMTime(seconds: prepared.duration, preferredTimescale: 60000))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? VideoWorkError.failed(L("HDR 导出未完成")) }
        } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
    }
}

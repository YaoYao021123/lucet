import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Photos
import Testing
import UniformTypeIdentifiers
@testable import MediaCore

struct ColorPipelineTests {
    @Test func hdrEffectKeepsMidtonesAndExpandsHighlightsWithoutHueShift() throws {
        let gray = pixel([0.3, 0.3, 0.3, 1], space: ColorPipeline.linearSpace)
        let dark = samples(try HDRExpansion.image(gray), space: ColorPipeline.linearSpace)
        #expect(abs(dark[0] - 0.3) < 0.005)
        let white = samples(try HDRExpansion.image(pixel([1, 1, 1, 1], space: ColorPipeline.linearSpace)), space: ColorPipeline.linearSpace)
        #expect(white[0] > 1.9 && white[0] < 2.01)
        let color = samples(try HDRExpansion.image(pixel([1, 0.8, 0.6, 1], space: ColorPipeline.linearSpace)), space: ColorPipeline.linearSpace)
        #expect(color[0] > 1)
        #expect(abs(color[1] / color[0] - 0.8) < 0.005)
        #expect(abs(color[2] / color[0] - 0.6) < 0.005)
    }
    @Test func rec709CreativeCubeUsesDeclaredTransferFunction() throws {
        let table = try table { r, g, b in [1 - r, g, b] }
        let lut = CreativeLUT(cube: table.cube, name: "Rec.709 test", encoding: .rec709)
        let input = pixel([0.2, 0.4, 0.6, 1], space: LUTEncoding.rec709.colorSpace)
        let full = samples(try ColorPipeline.grade(input, edits: .init(lut: lut)), space: LUTEncoding.rec709.colorSpace)
        #expect(abs(full[0] - 0.8) < 0.005)
        #expect(abs(full[1] - 0.4) < 0.005)
        let half = samples(try ColorPipeline.grade(input, edits: .init(lut: lut, strength: 0.5)), space: LUTEncoding.rec709.colorSpace)
        #expect(abs(half[0] - 0.5) < 0.005)
        let wrong = samples(try ColorPipeline.grade(input, edits: .init(lut: table)), space: LUTEncoding.rec709.colorSpace)
        #expect(abs(wrong[0] - full[0]) > 0.01)
    }
    @Test func creativeCubeWorksInEncodedSRGBAndStrengthInterpolates() throws {
        let lut = try table { r, g, b in [1 - r, g, b] }
        let input = pixel([0.2, 0.4, 0.6, 1])
        let full = samples(try ColorPipeline.grade(input, edits: .init(lut: lut)), space: ColorPipeline.outputSpace)
        #expect(abs(full[0] - 0.8) < 0.005)
        #expect(abs(full[1] - 0.4) < 0.005)
        let half = samples(try ColorPipeline.grade(input, edits: .init(lut: lut, strength: 0.5)), space: ColorPipeline.outputSpace)
        #expect(abs(half[0] - 0.5) < 0.005)
        let zero = samples(try ColorPipeline.grade(input, edits: .init(lut: lut, strength: 0)), space: ColorPipeline.outputSpace)
        #expect(abs(zero[0] - 0.2) < 0.005)
    }
    @Test func nonDefaultCubeDomainIsNormalizedBeforeInterpolation() throws {
        let lut = try table(domain: "DOMAIN_MIN 0.2 0.2 0.2\nDOMAIN_MAX 0.8 0.8 0.8") { [$0, $1, $2] }
        let value = samples(try ColorPipeline.grade(pixel([0.35, 0.5, 0.65, 1]), edits: .init(lut: lut)), space: ColorPipeline.outputSpace)
        #expect(abs(value[0] - 0.25) < 0.005)
        #expect(abs(value[1] - 0.5) < 0.005)
        #expect(abs(value[2] - 0.75) < 0.005)
    }
    @Test func floatingHDRSurvivesPreviewAndExplicitSDRToneMapping() throws {
        let input = pixel([4, 2, 1, 1], space: ColorPipeline.linearSpace)
        let unchanged = samples(try ColorPipeline.grade(input, edits: .init(), sourceHeadroom: 4), space: ColorPipeline.linearSpace)
        #expect(unchanged[0] > 3.9)
        let mapped = samples(ColorPipeline.toneMap(input, sourceHeadroom: 4), space: ColorPipeline.linearSpace)
        #expect(mapped[0] < unchanged[0] && mapped[0] > mapped[1])
        // Headroom measures luminance; saturated colors can legitimately have
        // an RGB component above 1 even after luminance tone mapping.
        let white = samples(ColorPipeline.toneMap(pixel([4, 4, 4, 1], space: ColorPipeline.linearSpace), sourceHeadroom: 4), space: ColorPipeline.linearSpace)
        #expect(white[0] <= 1.001 && white[0] > 0.9)
        let graded = samples(try ColorPipeline.grade(input, edits: .init(lut: .warm), sourceHeadroom: 4), space: ColorPipeline.linearSpace)
        #expect(graded[0] <= 1.001 && graded[3] > 0.99)
    }
    @Test func gradedExportUsesSamePixelsAndNeverOverwritesSource() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.png"), output = folder.appendingPathComponent("graded.png")
        let input = pixel([0.2, 0.4, 0.6, 1]).transformed(by: .init(scaleX: 120, y: 80))
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try ColorPipeline.sdrBitmap(input), nil)
        try #require(CGImageDestinationFinalize(destination))
        let before = try Data(contentsOf: source)
        var a = BasicAdjustments(); a.exposure = 0.25; a.warmth = 15; a.highlights = -20
        let edits = MediaEdits(degrees: 3, lut: .warm, strength: 0.6, adjustments: a)
        let frame = try await ImageGradeSession(url: source).frame(edits: edits)
        try ColorPipeline.exportPNG(source, to: output, edits: edits)
        let exported = try ImageGradeSession.decode(output)
        let previewValues = samples(frame.image, space: ColorPipeline.outputSpace)
        let exportValues = samples(exported, space: ColorPipeline.outputSpace)
        #expect(zip(previewValues, exportValues).allSatisfy { abs($0 - $1) < 0.01 })
        #expect(throws: (any Error).self) { try ColorPipeline.exportPNG(source, to: source, edits: edits) }
        #expect(try Data(contentsOf: source) == before)
    }
    @Test func gainMapHEICReopensWithHDRHeadroomAndFloatingPreview() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".heic")
        defer { try? FileManager.default.removeItem(at: url) }
        let bright = pixel([4, 4, 4, 1], space: ColorPipeline.linearSpace).transformed(by: .init(scaleX: 320, y: 180))
        let dark = pixel([0.2, 0.2, 0.2, 1], space: ColorPipeline.linearSpace).transformed(by: .init(scaleX: 160, y: 180))
        let hdr = dark.composited(over: bright)
        let sdr = ColorPipeline.toneMap(hdr, sourceHeadroom: 4)
        try ColorPipeline.context().writeHEIFRepresentation(of: sdr, to: url, format: .RGBA8,
            colorSpace: ColorPipeline.outputSpace, options: [.hdrImage: hdr])
        let decoded = try ImageGradeSession.decode(url)
        #expect(decoded.contentHeadroom > 1)
        let frame = try await ImageGradeSession(url: url).frame(edits: .init())
        #expect(frame.sourceHeadroom > 1)
        let brightRect = frame.image.cropped(to: CGRect(x: 200, y: 50, width: 10, height: 10))
        #expect(samples(brightRect, space: ColorPipeline.linearSpace)[0] > 1.2)
        if let path = ProcessInfo.processInfo.environment["WORKBENCH_TEST_ARTIFACTS"] {
            let target = URL(fileURLWithPath: path).appendingPathComponent("demo-HDR.heic")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: url, to: target) }
        }
    }
    private func table(domain: String = "", _ mapping: (Float, Float, Float) -> [Float]) throws -> CreativeLUT {
        var lines = ["LUT_3D_SIZE 2", domain]
        for b in [Float(0), 1] { for g in [Float(0), 1] { for r in [Float(0), 1] {
            lines.append(mapping(r,g,b).map(String.init(describing:)).joined(separator: " "))
        } } }
        return CreativeLUT(cube: try CubeLUT(text: lines.joined(separator: "\n")), name: "test")
    }
    private func pixel(_ values: [Float], space: CGColorSpace = ColorPipeline.outputSpace) -> CIImage {
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: 16, size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: space)
    }
    private func samples(_ image: CIImage, space: CGColorSpace) -> [Float] {
        var values = [Float](repeating: 0, count: 4)
        let center = CGRect(x: floor(image.extent.midX), y: floor(image.extent.midY), width: 1, height: 1)
        values.withUnsafeMutableBytes { bytes in
            ColorPipeline.context().render(image, toBitmap: bytes.baseAddress!, rowBytes: 16, bounds: center, format: .RGBAf, colorSpace: space)
        }
        return values
    }
}

struct VideoLiveTests {
    @Test func basicVideoPreviewAndLiveCoverShareTheSameGrade() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("source.mov")
        try await fixtureVideo(raw)
        var a = BasicAdjustments(); a.exposure = 0.4; a.warmth = 25; a.saturation = -15; a.shadows = 12
        let edits = MediaEdits(lut: .warm, strength: 0.3, adjustments: a)
        let clip = ClipSettings(start: 0.5, end: 2.5, cover: 1.25)
        let prepared = try await VideoPipeline.prepare(raw, clip: clip, edits: edits, sdr: true)
        let generator = AVAssetImageGenerator(asset: prepared.asset)
        generator.videoComposition = prepared.videoComposition
        let (preview, _) = try await generator.image(at: CMTime(seconds: clip.outputCover, preferredTimescale: 600))
        let resources = try await LivePhotoPipeline.export(raw, to: folder.appendingPathComponent("Live"), clip: clip, edits: edits)
        func rgb(_ image: CIImage) -> [Float] {
            var values = [Float](repeating: 0, count: 4)
            values.withUnsafeMutableBytes {
                ColorPipeline.context().render(image, toBitmap: $0.baseAddress!, rowBytes: 16,
                    bounds: CGRect(x: 10, y: 90, width: 1, height: 1), format: .RGBAf, colorSpace: ColorPipeline.outputSpace)
            }
            return values
        }
        let expected = rgb(CIImage(cgImage: preview))
        let actual = rgb(try ImageGradeSession.decode(resources.imageURL))
        #expect(zip(expected, actual).allSatisfy { abs($0 - $1) < 0.035 })
        let recipe = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("Live/recipe.json"))) as? [String: Any])
        let saved = try #require(recipe["adjustments"] as? [String: Double])
        #expect(saved["exposure"] == 0.4 && saved["warmth"] == 25)
    }

    @Test func canceledVideoExportNeverPublishesOutput() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("source.mov"), output = folder.appendingPathComponent("canceled.mov")
        try await fixtureVideo(raw)
        let task = Task {
            try await VideoPipeline.export(raw, to: output, clip: .init(start: 0, end: 3, cover: 1), edits: .init(lut: .warm))
        }
        task.cancel()
        do { try await task.value; Issue.record("取消后仍报告导出成功") } catch { }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".workbench-") })
    }

    @Test func previewUpdatesFiltersWithoutRebuildingAssetAndKeepsExportFullSize() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("preview-source.mov")
        try await fixtureVideo(raw)
        let clip = ClipSettings(start: 0, end: 2, cover: 1)
        let state = VideoPreviewState(edits: .init(lut: .warm, strength: 0), maximumDimension: 160)
        let prepared = try await VideoPipeline.prepare(raw, clip: clip, edits: state.snapshot(), sdr: true, preview: state)
        let composition = try #require(prepared.videoComposition)
        #expect(composition.renderSize == CGSize(width: 160, height: 90))
        func sample() async throws -> [Float] {
            let generator = AVAssetImageGenerator(asset: prepared.asset)
            generator.videoComposition = composition
            let (bitmap, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            #expect(bitmap.width == 160 && bitmap.height == 90)
            let average = CIImage(cgImage: bitmap).applyingFilter("CIAreaAverage", parameters: [
                kCIInputExtentKey: CIVector(cgRect: CGRect(x: 50, y: 25, width: 40, height: 40))
            ])
            var pixel = [Float](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes {
                ColorPipeline.context().render(average, toBitmap: $0.baseAddress!, rowBytes: 16,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: ColorPipeline.outputSpace)
            }
            return pixel
        }
        let original = try await sample()
        state.update(.init(lut: .warm, strength: 1))
        let graded = try await sample()
        #expect(graded[0] > original[0] + 0.01)
        #expect(graded[2] < original[2] - 0.005)
        state.update(.init(degrees: 5, lut: .soft, strength: 0.8))
        _ = try await sample()
        #expect(composition.renderSize == CGSize(width: 160, height: 90))
        let full = try await VideoPipeline.prepare(raw, clip: clip, edits: .init(lut: .warm), sdr: true)
        #expect(full.videoComposition?.renderSize == CGSize(width: 320, height: 180))
    }

    @Test func hdrEffectLiveRetainsRealBrightPixelsGainMapAndMusic() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov"), music = folder.appendingPathComponent("music.wav")
        try await fixtureVideo(source, highlights: true); try fixtureAudio(music)
        let clip = ClipSettings(start: 0, end: 3, cover: 1, musicURL: music, musicVolume: 0.3, speed: 2)
        let resources = try await LivePhotoPipeline.export(source, to: folder.appendingPathComponent("HDR-Live"), clip: clip,
            edits: .init(hdrEffect: true))
        let meta = try await MediaInspector.inspect(resources.videoURL)
        #expect(meta.transferFunction == AVVideoTransferFunction_ITU_R_2100_HLG)
        #expect(abs((meta.durationSeconds ?? 0) - 1.5) < 0.01)
        #expect(abs((meta.nominalFrameRate ?? 0) - 24) < 0.01)
        let image = try ImageGradeSession.decode(resources.imageURL)
        #expect(image.contentHeadroom > 1)
        let maximum = image.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixels = [Float](repeating: 0, count: 4)
        pixels.withUnsafeMutableBytes { ColorPipeline.context().render(maximum, toBitmap: $0.baseAddress!, rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: ColorPipeline.linearSpace) }
        #expect(pixels[0] > 1.2)
        #expect(try await LivePhotoPipeline.pairedMovie(for: resources.imageURL) == resources.videoURL)
        let rms = try await audioRMS(resources.videoURL)
        #expect(rms > 0.035 && rms < 0.05)
    }
    @Test func acceleratedLiveKeepsMusicDurationAndMapsCoverToOutputTime() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov"), music = folder.appendingPathComponent("music.wav")
        try await fixtureVideo(source); try fixtureAudio(music)
        let clip = ClipSettings(start: 0, end: 3, cover: 1, musicURL: music, musicVolume: 0.3, speed: 2)
        let target = folder.appendingPathComponent("Live")
        let resources = try await LivePhotoPipeline.export(source, to: target, clip: clip, edits: .init())
        let meta = try await MediaInspector.inspect(resources.videoURL)
        #expect(abs((meta.durationSeconds ?? 0) - 1.5) < 0.05)
        #expect(meta.hasAudio == true)
        #expect(abs((meta.nominalFrameRate ?? 0) - 24) < 0.01)
        #expect(abs(resources.coverSeconds - 0.5) < 0.05)
        let rms = try await audioRMS(resources.videoURL)
        #expect(rms > 0.035 && rms < 0.05)
    }
    @Test(arguments: [AVVideoTransferFunction_SMPTE_ST_2084_PQ, AVVideoTransferFunction_ITU_R_2100_HLG])
    func hdrVideoKeepsNativePreviewAndExportsRec709(_ transfer: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("hdr.mov"), output = folder.appendingPathComponent("sdr.mov")
        try await fixtureVideo(raw, transfer: transfer)
        let metadata = try await MediaInspector.inspect(raw)
        #expect(metadata.transferFunction == transfer)
        let clip = ClipSettings(start: 0, end: 2, cover: 1)
        let native = try await VideoPipeline.prepare(raw, clip: clip, edits: .init(), sdr: false)
        #expect(native.videoComposition == nil)
        let generator = AVAssetImageGenerator(asset: native.asset)
        generator.dynamicRangePolicy = .matchSource
        let (bitmap, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        #expect(bitmap.colorSpace?.isHDR() == true)
        try await VideoPipeline.export(raw, to: output, clip: clip, edits: .init(lut: .warm))
        let converted = try await MediaInspector.inspect(output)
        #expect(converted.transferFunction == AVVideoTransferFunction_ITU_R_709_2)
        #expect(abs((converted.durationSeconds ?? 0) - 2) < 0.06)
        if let path = ProcessInfo.processInfo.environment["WORKBENCH_TEST_ARTIFACTS"] {
            let target = URL(fileURLWithPath: path).appendingPathComponent(transfer == AVVideoTransferFunction_ITU_R_2100_HLG ? "demo-HLG.mov" : "demo-PQ.mov")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: raw, to: target) }
        }
    }
    @Test func invalidAndOversizedLiveRangesAreRejected() {
        #expect(throws: VideoWorkError.self) { try ClipSettings(start: 0, end: 3.05, cover: 1).validate(duration: 10, live: true) }
        for clip in [ClipSettings(start: -1, end: 2, cover: 1), .init(start: 1, end: 1, cover: 1),
                     .init(start: 0, end: 2, cover: 2), .init(start: 0, end: 4, cover: 2),
                     .init(start: 0, end: 2, cover: .nan)] {
            #expect(throws: VideoWorkError.self) { try clip.validate(duration: 3, live: true) }
        }
    }

    @Test func videoAndLiveRoundTripApplyGradeAudioCoverAndPairing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("source.mov"), music = folder.appendingPathComponent("tone.wav")
        try await fixtureVideo(raw)
        try fixtureAudio(music)
        let before = try Data(contentsOf: raw)
        let clip = ClipSettings(start: 0.5, end: 2.5, cover: 1.25, originalVolume: 0, musicURL: music, musicVolume: 0.3)
        let edits = MediaEdits(degrees: 2, lut: .warm, strength: 0.6)
        let output = folder.appendingPathComponent("graded.mov")
        try await VideoPipeline.export(raw, to: output, clip: clip, edits: edits)
        let metadata = try await MediaInspector.inspect(output)
        #expect(abs((metadata.durationSeconds ?? 0) - 2) < 0.06)
        #expect(metadata.hasAudio == true)
        #expect(metadata.transferFunction == AVVideoTransferFunction_ITU_R_709_2)
        #expect(metadata.displayWidth < 320 && metadata.displayHeight < 180)
        let rms = try await audioRMS(output)
        #expect(rms > 0.035 && rms < 0.05) // 0.2-amplitude sine × 0.3, AAC tolerance.
        let movieBefore = try Data(contentsOf: output)
        await #expect(throws: (any Error).self) { try await VideoPipeline.export(raw, to: output, clip: clip, edits: edits) }
        #expect(try Data(contentsOf: output) == movieBefore)
        let liveDir = folder.appendingPathComponent("Live")
        let resources = try await LivePhotoPipeline.export(raw, to: liveDir, clip: clip, edits: edits)
        let savedLUT = try CubeLUT(text: String(contentsOf: liveDir.appendingPathComponent("lut.cube"), encoding: .utf8))
        #expect(savedLUT.rgb == CreativeLUT.warm.cube.rgb)
        let pair = try await LivePhotoPipeline.pairedMovie(for: resources.imageURL)
        #expect(pair == resources.videoURL)
        let reopenedCover = try #require(try await LivePhotoPipeline.coverTime(in: resources.videoURL))
        #expect(abs(reopenedCover - resources.coverSeconds) < 0.001)
        let photo = try await LivePhotoPipeline.load(imageURL: resources.imageURL, videoURL: resources.videoURL)
        #expect(photo.size.width > 0 && photo.size.height > 0)
        let pairedAsset = AVURLAsset(url: resources.videoURL)
        let timedTrack = try #require(try await pairedAsset.loadTracks(withMediaType: .metadata).first)
        let reader = try AVAssetReader(asset: pairedAsset)
        let trackOutput = AVAssetReaderTrackOutput(track: timedTrack, outputSettings: nil)
        reader.add(trackOutput)
        let metadataReader = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: trackOutput)
        try #require(reader.startReading())
        let group = try #require(metadataReader.nextTimedMetadataGroup())
        #expect(abs(group.timeRange.start.seconds - resources.coverSeconds) < 0.001)
        #expect(abs(resources.coverSeconds - 0.75) < 1.0 / 24)
        #expect(group.items.first?.identifier?.rawValue == "mdta/com.apple.quicktime.still-image-time")
        #expect(try Data(contentsOf: raw) == before)
        if let path = ProcessInfo.processInfo.environment["WORKBENCH_TEST_ARTIFACTS"] {
            let target = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for (file, name) in [(raw, "demo-video.mov"), (music, "demo-bgm.wav"), (output, "graded-video.mov"), (liveDir, "demo-Live")] {
                let destination = target.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: file, to: destination) }
            }
        }
    }

    @Test func liveCollageKeepsIndependentGradesPanelOrderAndSourceTiming() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = folder.appendingPathComponent("source.mov")
        try await fixtureVideo(raw)
        let original = try Data(contentsOf: raw)
        var dark = BasicAdjustments(); dark.exposure = -1
        let top = LiveCollagePane(url: raw, clip: .init(start: 0, end: 1, cover: 0.5), edits: .init())
        let lower = LiveCollagePane(url: raw, clip: .init(start: 0, end: 2, cover: 1, speed: 2), edits: .init(adjustments: dark))
        let bottom = LiveCollagePane(url: raw, clip: .init(start: 1, end: 1.5, cover: 1.25, speed: 0.5), edits: .init())
        for panes in [[top, lower], [top, lower, bottom]] {
            let target = folder.appendingPathComponent("Live-\(panes.count)")
            let result = try await LiveCollagePipeline.export(panes, to: target)
            _ = try await LivePhotoPipeline.load(imageURL: result.imageURL, videoURL: result.videoURL)
            #expect(try await LivePhotoPipeline.pairedMovie(for: result.imageURL) == result.videoURL)
            let metadata = try await MediaInspector.inspect(result.videoURL)
            #expect(metadata.displayWidth == 1080 && metadata.displayHeight == 608 * panes.count)
            #expect(abs((metadata.durationSeconds ?? 0) - 1) < 0.04)
            let image = try ImageGradeSession.decode(result.imageURL)
            func sample(_ row: Int) -> [Float] {
                var rgba = [Float](repeating: 0, count: 4)
                rgba.withUnsafeMutableBytes {
                    ColorPipeline.context().render(image, toBitmap: $0.baseAddress!, rowBytes: 16,
                        bounds: CGRect(x: 10, y: CGFloat(panes.count - row - 1) * 608 + 304, width: 1, height: 1),
                        format: .RGBAf, colorSpace: ColorPipeline.outputSpace)
                }
                return rgba
            }
            let upper = sample(0), lowerSample = sample(1)
            #expect(upper[2] > upper[0] && lowerSample[2] > lowerSample[0])
            #expect(upper[2] - lowerSample[2] > 0.1) // top must retain its brighter grade
            if panes.count == 3 { #expect(abs(sample(2)[2] - upper[2]) < 0.05) }
            let recipe = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent("recipe.json"))) as? [String: Any])
            let saved = try #require(recipe["panes"] as? [[String: Any]])
            #expect(saved.count == panes.count && saved[1]["speed"] as? Double == 2)
            await #expect(throws: VideoWorkError.self) { try await LiveCollagePipeline.export(panes, to: target) }
        }
        #expect(try Data(contentsOf: raw) == original)
        let target = folder.appendingPathComponent("Canceled")
        let task = Task { try await LiveCollagePipeline.export([top, lower], to: target) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
    @Test func invalidCollageRejectsMismatchedDurationsAndHDRBeforeExport() throws {
        let url = URL(fileURLWithPath: "/missing.mov")
        let pane = LiveCollagePane(url: url, clip: .init(start: 0, end: 3, cover: 1.5), edits: .init())
        let short = LiveCollagePane(url: url, clip: .init(start: 0, end: 2, cover: 1), edits: .init())
        let hdr = LiveCollagePane(url: url, clip: pane.clip, edits: .init(hdrEffect: true))
        #expect(throws: VideoWorkError.self) { try LiveCollagePipeline.validate([]) }
        #expect(throws: VideoWorkError.self) { try LiveCollagePipeline.validate([pane, short]) }
        #expect(throws: VideoWorkError.self) { try LiveCollagePipeline.validate([hdr]) }
        #expect(throws: VideoWorkError.self) { try LiveCollagePipeline.validate([pane, pane, pane, pane]) }
    }

    private func fixtureVideo(_ output: URL, transfer: String? = nil, highlights: Bool = false) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        var settings: [String: Any] = [AVVideoCodecKey: transfer == nil ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            AVVideoWidthKey: 320, AVVideoHeightKey: 180,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: transfer == nil ? AVVideoColorPrimaries_ITU_R_709_2 : AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: transfer ?? AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: transfer == nil ? AVVideoYCbCrMatrix_ITU_R_709_2 : AVVideoYCbCrMatrix_ITU_R_2020]]
        if transfer != nil { settings[AVVideoCompressionPropertiesKey] = [AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel"] }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: transfer == nil ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(input); try #require(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        let context = ColorPipeline.context()
        for index in 0..<72 {
            while !input.isReadyForMoreMediaData {
                try #require(writer.status == .writing)
                try await Task.sleep(for: .milliseconds(2))
            }
            var buffer: CVPixelBuffer?
            try #require(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, try #require(adaptor.pixelBufferPool), &buffer) == kCVReturnSuccess)
            let pixel = try #require(buffer)
            let base = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.65)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
            let stripe = CIImage(color: CIColor(red: 0.8, green: 0.4, blue: 0.15)).cropped(to: CGRect(x: index * 4, y: 30, width: 30, height: 110))
            let space = transfer == nil ? ColorPipeline.outputSpace : CGColorSpace(name: transfer == AVVideoTransferFunction_ITU_R_2100_HLG ? CGColorSpace.itur_2100_HLG : CGColorSpace.itur_2100_PQ)!
            var image = stripe.composited(over: base)
            if highlights {
                let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 10, y: 10, width: 60, height: 60))
                image = white.composited(over: image)
            }
            context.render(image, to: pixel, bounds: base.extent, colorSpace: space)
            try #require(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 24)))
        }
        input.markAsFinished(); await writer.finishWriting()
        try #require(writer.status == .completed)
    }
    private func fixtureAudio(_ output: URL) throws {
        let rate = 48000, count = rate * 3
        var samples = [Int16](); samples.reserveCapacity(count)
        for index in 0..<count { samples.append(Int16(sin(Double(index) * 2 * .pi * 440 / Double(rate)) * 0.2 * 32767)) }
        var data = Data()
        func string(_ value: String) { data.append(Data(value.utf8)) }
        func uint32(_ value: UInt32) { var le = value.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        func uint16(_ value: UInt16) { var le = value.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        string("RIFF"); uint32(UInt32(36 + count * 2)); string("WAVEfmt "); uint32(16); uint16(1); uint16(1)
        uint32(UInt32(rate)); uint32(UInt32(rate * 2)); uint16(2); uint16(16); string("data"); uint32(UInt32(count * 2))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }; try data.write(to: output)
    }
    private func audioRMS(_ url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(output); try #require(reader.startReading())
        var sum = 0.0, count = 0
        while let sample = output.copyNextSampleBuffer() {
            let block = try #require(CMSampleBufferGetDataBuffer(sample))
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            try data.withUnsafeMutableBytes { bytes in try #require(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!) == noErr) }
            data.withUnsafeBytes { bytes in for value in bytes.bindMemory(to: Float.self) { sum += Double(value * value); count += 1 } }
        }
        try #require(count > 0); return sqrt(sum / Double(count))
    }
}

import CoreImage
import Foundation
import ImageIO
import Testing
@testable import MediaCore

struct AutoHDRTests {
    private func map(_ channels: Int, _ height: Int, _ width: Int, _ value: (Int, Int, Int) -> Double) -> AutoHDR.Map {
        var data = [Float](repeating: 0, count: channels * height * width)
        for c in 0..<channels { for y in 0..<height { for x in 0..<width { data[(c * height + y) * width + x] = Float(value(c, y, x)) } } }
        return AutoHDR.Map(channels: channels, height: height, width: width, data: data)
    }

    @Test func testNetworkMatchesTheReferenceImplementation() throws {
        let model = try #require(AutoHDR.shared, "assets/models/gmnet-realworld.bin should load")
        let global = map(3, 16, 16) { c, y, x in 0.5 + 0.45 * sin(0.37 * Double(x) + 0.23 * Double(y) + 1.1 * Double(c)) }
        let local = map(3, 8, 8) { c, y, x in 0.5 + 0.45 * cos(0.41 * Double(x) - 0.29 * Double(y) + 0.7 * Double(c)) }
        let (out, qmax) = model.network(global: global, local: local)
        #expect(out.channels == 1 && out.height == 8 && out.width == 8)
        // Computed by an independent plain-Python forward pass written from the published GMNet.py.
        #expect(abs(qmax - 0.116749) < 1e-4, "\(qmax)")
        for (index, value) in [(0, 0.523213), (9, 0.740173), (27, 0.67728), (36, 0.626348), (50, 0.86553), (63, 0.45628)] as [(Int, Float)] {
            #expect(abs(out.data[index] - value) < 1e-3, "\(index): \(out.data[index])")
        }
        // Done in bands of rows, the result is the same.
        let banded = model.network(global: global, local: local, tailRows: 1).out
        #expect(zip(banded.data, out.data).allSatisfy { abs($0 - $1) < 1e-5 })
        let gain = model.gainMap(global: global, local: local)
        #expect(gain.data.allSatisfy { $0 >= 0 && $0 <= Float(AutoHDR.maxStops) })
    }

    /// An ordinary JPEG: a dusky sky with a bright sun.
    private func sunset(in folder: URL) throws -> URL {
        let sky = CIImage(color: CIColor(red: 0.25, green: 0.3, blue: 0.45)).cropped(to: CGRect(x: 0, y: 0, width: 480, height: 320))
        let disc = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 320, y: 220), "inputRadius0": 30, "inputRadius1": 46,
            "inputColor0": CIColor(red: 1, green: 0.98, blue: 0.92), "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        ])!.outputImage!.cropped(to: sky.extent)
        let picture = disc.composited(over: sky)
        let url = folder.appendingPathComponent("sunset.jpg")
        let data = try #require(ColorPipeline.shared.jpegRepresentation(of: picture, colorSpace: ColorPipeline.outputSpace))
        try data.write(to: url)
        return url
    }

    private func gainMaps(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap]
            .filter { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }.count
    }

    private func peak(_ image: CIImage) -> Float {
        var out = [Float](repeating: 0, count: 4)
        let probe = image.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        out.withUnsafeMutableBytes {
            ColorPipeline.shared.render(probe, toBitmap: $0.baseAddress!, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                        format: .RGBAf, colorSpace: ColorPipeline.linearSpace)
        }
        return out[1]
    }

    @Test func testOrdinaryPhotosGlowOnHDRScreensAndExportAGainMap() async throws {
        let model = try #require(AutoHDR.shared)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("autohdr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try sunset(in: folder)

        let gain = try #require(model.gain(for: source))
        #expect(gain.extent.width > 0 && gain.extent.height > 0)
        // The sun is lifted more than the sky.
        func gainAt(_ x: CGFloat, _ y: CGFloat) -> Float {
            let fx = x / 480 * gain.extent.width, fy = y / 320 * gain.extent.height
            var value: Float = 0
            ColorPipeline.shared.render(gain, toBitmap: &value, rowBytes: 4, bounds: CGRect(x: fx, y: fy, width: 1, height: 1), format: .Rf, colorSpace: nil)
            return value
        }
        #expect(gainAt(320, 220) > gainAt(80, 60) + 0.05, "sun \(gainAt(320, 220)), sky \(gainAt(80, 60))")

        var edits = MediaEdits()
        let session = try ImageGradeSession(url: source)
        #expect(try await session.frame(edits: edits).headroom == 1)
        edits.hdrAmount = 1
        let frame = try await session.frame(edits: edits)
        #expect(frame.headroom > 4.9)
        #expect(peak(frame.image) > 1.05, "the preview goes past SDR white")

        var options = ImageExportOptions()
        options.format = .jpeg
        let off = folder.appendingPathComponent("off.jpg"), on = folder.appendingPathComponent("on.heic")
        try ImageExporter.export(source, to: off, edits: MediaEdits(), options: options)
        #expect(gainMaps(off) == 0)
        options.format = .heic
        try ImageExporter.export(source, to: on, edits: edits, options: options)
        #expect(gainMaps(on) > 0)
        #expect(peak(try ImageGradeSession.decode(on)) > 1.05)
        // Ordinary screens see the photo as it was.
        let plain = try #require(CIImage(contentsOf: on))
        #expect(peak(plain) <= 1.001)
    }

    @Test func testRecipesAndProjectsKeepTheStrength() throws {
        var recipe = EditRecipe()
        recipe.hdrAmount = 0.6
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded.hdrAmount == 0.6)
        #expect(MediaEdits(recipe: decoded, lut: nil).hdrAmount == 0.6)
        #expect(MediaEdits(recipe: decoded, lut: nil, isVideo: true).hdrAmount == 0.6, "kept for the Live Photo cover")
        let old = try JSONDecoder().decode(EditRecipe.self, from: Data(#"{"version":1}"#.utf8))
        #expect(old.hdrAmount == 0)
        let wild = try JSONDecoder().decode(EditRecipe.self, from: Data(#"{"version":1,"hdrAmount":7}"#.utf8))
        #expect(wild.hdrAmount == 1)

        var project = Project(name: "Trip")
        project.add(["/a.jpg", "/b.jpg"])
        var edited = project.recipe(for: "/a.jpg")!
        let previous = edited
        edited.hdrAmount = 0.8
        project.store(edited, for: "/a.jpg", previous: previous, photoOnly: false)
        #expect(project.recipe(for: "/a.jpg")?.hdrAmount == 0.8)
        #expect(project.recipe(for: "/b.jpg")?.hdrAmount == 0, "per photo, not shared")
    }

    @Test func testMotionGlowIsSmoothedOverTime() throws {
        // A map that flickers on and off from frame to frame settles toward its average.
        var maps: [[Float]] = [[0], [1], [0], [1], [0], [1]]
        func flicker(_ maps: [[Float]]) -> Float { zip(maps, maps.dropFirst()).map { abs($0[0] - $1[0]) }.max() ?? 0 }
        let before = flicker(maps)
        maps = AutoHDR.smoothed(maps)
        #expect(maps[1] == [0.5] && maps[0] == [0.25])
        #expect(flicker(AutoHDR.smoothed(maps)) < before / 3)
        // Two maps or fewer are left as they are.
        #expect(AutoHDR.smoothed([[0], [1]]) == [[0], [1]])
    }

    @Test func testRefusesADamagedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("GMNT\u{1}\0\0\0\u{40}\0\0\0[]".utf8).write(to: url)
        #expect(throws: (any Error).self) { try AutoHDR(contentsOf: url) }
    }
}

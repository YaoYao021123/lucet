import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaCore

struct StraighteningTests {
    @Test func safeCropStaysInsideSourceForBothRotationDirections() throws {
        for (width, height) in [(4000, 3000), (3000, 4000), (4096, 1024), (128, 128)] {
            for degrees in [-10.0, -3, 0, 3, 10, 45] {
                let plan = try StraighteningPlan(width: width, height: height, rotationRadians: degrees * .pi / 180)
                let rect = plan.cropRect
                let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                               CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
                for corner in corners {
                    let source = corner.applying(plan.transform.inverted())
                    #expect(source.x >= -1e-8 && source.x <= Double(width) + 1e-8)
                    #expect(source.y >= -1e-8 && source.y <= Double(height) + 1e-8)
                }
                #expect(abs(Double(plan.outputWidth) / Double(plan.outputHeight) - Double(width) / Double(height)) < 0.15)
                if degrees == 0 { #expect(plan.outputWidth == width && plan.outputHeight == height) }
            }
        }
    }

    @Test func unsafeAutomaticSuggestionsDoNotProduceAnAppliedPlan() throws {
        let missing = try StraighteningAssessment.evaluate(width: 4000, height: 3000, radians: nil, confidence: nil)
        #expect(missing.status == .noReference && missing.plan == nil)
        for (angle, score) in [(3.0, Float(0.2)), (20.0, 1), (Double.nan, 1)] {
            let result = try StraighteningAssessment.evaluate(width: 4000, height: 3000, radians: angle * .pi / 180, confidence: score)
            #expect(result.plan == nil)
        }
        let wide = try StraighteningAssessment.evaluate(width: 4000, height: 500, radians: 10 * .pi / 180, confidence: 1)
        #expect(wide.status == .reviewRequired && wide.plan == nil)
        let level = try StraighteningAssessment.evaluate(width: 4000, height: 3000, radians: 0, confidence: 1)
        #expect(level.status == .alreadyLevel && level.plan == nil)
        let valid = try StraighteningAssessment.evaluate(width: 4000, height: 3000, radians: -3 * .pi / 180, confidence: 0.9)
        #expect(valid.status == .ready)
        #expect(abs(try #require(valid.plan).rotationDegrees + 3) < 1e-9)
    }

    @Test func rejectsInvalidGeometry() {
        for (width, height, angle) in [(0, 100, 0.0), (100, 1, 0), (100, 100, Double.infinity), (100, 100, 1)] {
            #expect(throws: StraighteningError.self) {
                try StraighteningPlan(width: width, height: height, rotationRadians: angle)
            }
        }
    }

    @Test func previewAndExportHaveNoTransparentBordersAndDoNotOverwrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.png")
        try fixture(to: input)
        let original = try Data(contentsOf: input)
        for degrees in [-10.0, 0, 10] {
            let preview = try ImageStraightener.preview(input, degrees: degrees)
            try assertOpaque(preview)
            let output = directory.appendingPathComponent("output-\(degrees).png")
            let plan = try ImageStraightener.exportPNG(input, to: output, degrees: degrees)
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == plan.outputWidth && image.height == plan.outputHeight)
            try assertOpaque(image)
            let before = try Data(contentsOf: output)
            #expect(throws: (any Error).self) {
                try ImageStraightener.exportPNG(input, to: output, degrees: 3)
            }
            #expect(try Data(contentsOf: output) == before)
        }
        #expect(throws: (any Error).self) { try ImageStraightener.exportPNG(input, to: input, degrees: 3) }
        #expect(try Data(contentsOf: input) == original)
    }

    @Test func uprightPreviewAndFullExportApplyExifOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for orientation in 1...8 {
            let input = directory.appendingPathComponent("input-\(orientation).jpg")
            let output = directory.appendingPathComponent("output-\(orientation).png")
            try fixture(to: input, orientation: orientation)
            let preview = try ImageStraightener.preview(input, degrees: 0)
            let plan = try ImageStraightener.exportPNG(input, to: output, degrees: 0)
            #expect(preview.width == plan.outputWidth && preview.height == plan.outputHeight)
            #expect(plan.sourceWidth == ((5...8).contains(orientation) ? 60 : 100))
            let exported = try ImageStraightener.preview(output, degrees: 0)
            #expect(exported.width == preview.width && exported.height == preview.height)
            // Compare pixels in a common RGBA context: mirrors/rotations must agree,
            // not just the dimensions (JPEG input is decoded along both paths).
            let p = try pixels(preview), e = try pixels(exported)
            let difference = zip(p, e).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(difference <= 3)
            // The HDR/LUT workspace now uses a different floating-point decode
            // path; verify all eight EXIF orientations there independently too.
            let gradeFrame = try await ImageGradeSession(url: input).frame(edits: .init())
            let gradePreview = try ColorPipeline.sdrBitmap(gradeFrame.image, headroom: gradeFrame.headroom)
            let gradeOutput = directory.appendingPathComponent("grade-\(orientation).png")
            try ColorPipeline.exportPNG(input, to: gradeOutput, edits: .init())
            let gradeExport = try ImageStraightener.preview(gradeOutput, degrees: 0)
            #expect(gradePreview.width == gradeExport.width && gradePreview.height == gradeExport.height)
            #expect(gradePreview.width == plan.sourceWidth && gradePreview.height == plan.sourceHeight)
            let gp = try pixels(gradePreview), ge = try pixels(gradeExport)
            #expect((zip(gp, ge).map { abs(Int($0) - Int($1)) }.max() ?? 0) <= 3)
        }
    }

    @Test func visionRequestRunsOnOrientedThumbnail() async throws {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: input) }
        try fixture(to: input, orientation: 6)
        let assessment = try await ImageStraightener.analyze(input)
        #expect(assessment.detectorRevision == 1)
        if let confidence = assessment.confidence { #expect(confidence.isFinite) }
        if let plan = assessment.plan { #expect(plan.sourceWidth == 60 && plan.sourceHeight == 100) }
        // This is an API smoke test, not an accuracy claim for the synthetic fixture.
    }

    private func fixture(to url: URL, orientation: Int = 1) throws {
        let context = try #require(CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.6, green: 0.7, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 70, height: 20))
        let type = url.pathExtension == "jpg" ? UTType.jpeg : UTType.png
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4))
    }

    private func assertOpaque(_ image: CGImage) throws {
        let bytes = try pixels(image)
        #expect(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
    }
}

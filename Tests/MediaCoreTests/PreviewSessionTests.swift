import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaCore

struct PreviewSessionTests {
    @Test func cachedSessionRendersAfterSourceIsRemovedAndMatchesExistingPipeline() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let canvas = try #require(CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(CGColor(red: 0.6, green: 0.5, blue: 0.3, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(canvas.makeImage()), nil)
        try #require(CGImageDestinationFinalize(destination))
        let expected = try ImageStraightener.preview(url, degrees: 3)
        let session = try ImagePreviewSession(url: url)
        let original = try await session.render(degrees: 0)
        try FileManager.default.removeItem(at: url)
        let actual = try await session.render(degrees: 3)
        #expect(actual.width == expected.width && actual.height == expected.height)
        let a = try #require(actual.dataProvider?.data) as Data
        let b = try #require(expected.dataProvider?.data) as Data
        #expect(a == b)
        let restored = try await session.render(degrees: 0)
        #expect(original === restored)
    }
}

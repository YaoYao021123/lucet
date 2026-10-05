import CoreImage
import Foundation
import Testing
@testable import MediaCore

struct GeometryAdjustmentTests {
    private func sample(_ image: CIImage, x: Int, y: Int) -> [Float] {
        var values = [Float](repeating: 0, count: 4)
        values.withUnsafeMutableBytes { ColorPipeline.context().render(image, toBitmap: $0.baseAddress!, rowBytes: 16,
            bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: ColorPipeline.outputSpace) }
        return values
    }
    @Test func quarterRotationAndMirrorPreserveExpectedCornerPixels() throws {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
        let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 20, y: 0, width: 20, height: 20)).composited(over: red)
        var g = GeometryAdjustments(); g.quarterTurns = 1
        let rotated = try ColorPipeline.geometry(green, edits: .init(geometry: g))
        #expect(rotated.extent.size == CGSize(width: 20, height: 40))
        #expect(sample(rotated, x: 10, y: 5)[0] > 0.98)
        #expect(sample(rotated, x: 10, y: 35)[1] > 0.98)
        g.quarterTurns = 0; g.mirrored = true
        let mirrored = try ColorPipeline.geometry(green, edits: .init(geometry: g))
        #expect(sample(mirrored, x: 5, y: 5)[1] > 0.98)
        #expect(sample(mirrored, x: 35, y: 5)[0] > 0.98)
    }
    @Test func repositionedSquareCropMatchesDeclaredExportSizeAndIsOpaque() throws {
        let source = CIImage(color: CIColor(red: 0.3, green: 0.6, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
        for x in [-100.0, 0, 100] {
            var g = GeometryAdjustments(); g.aspectRatio = 1; g.cropScale = 0.5; g.horizontal = x; g.vertical = 100
            let edits = MediaEdits(degrees: 3, geometry: g)
            let image = try ColorPipeline.geometry(source, edits: edits)
            #expect(image.extent.size == (try ColorPipeline.geometrySize(width: 320, height: 180, edits: edits)))
            for p in [(1,1), (Int(image.extent.width) - 2, Int(image.extent.height) - 2)] {
                #expect(sample(image, x: p.0, y: p.1)[3] > 0.99)
            }
        }
    }
    @Test func geometryRejectsInvalidCropAndLegacyRecipeUsesOriginalFrame() throws {
        var g = GeometryAdjustments(); g.cropScale = 0
        #expect(throws: (any Error).self) { try g.validate() }
        let old = Data("{\"version\":1,\"degrees\":2,\"strength\":0.5}".utf8)
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: old)
        #expect(recipe.geometry == .init() && recipe.adjustments.isNeutral)
        try recipe.validate()
    }
}

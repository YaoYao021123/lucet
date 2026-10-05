import CoreImage
import Foundation
import Testing
@testable import MediaCore

struct BasicAdjustmentTests {
    private func pixel(_ values: [Float], linear: Bool = false) -> CIImage {
        CIImage(bitmapData: values.withUnsafeBytes { Data($0) }, bytesPerRow: 16, size: CGSize(width: 1, height: 1),
                format: .RGBAf, colorSpace: linear ? ColorPipeline.linearSpace : ColorPipeline.outputSpace)
    }
    private func sample(_ image: CIImage, linear: Bool = false, x: Int = 0, y: Int = 0) -> [Float] {
        var values = [Float](repeating: 0, count: 4)
        values.withUnsafeMutableBytes {
            ColorPipeline.context().render(image, toBitmap: $0.baseAddress!, rowBytes: 16,
                bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf,
                colorSpace: linear ? ColorPipeline.linearSpace : ColorPipeline.outputSpace)
        }
        return values
    }
    private func tune(_ values: [Float], _ parameter: AdjustmentParameter, _ value: Double, linear: Bool = false) throws -> [Float] {
        var adjustments = BasicAdjustments(); adjustments[parameter] = value
        return sample(try ColorPipeline.grade(pixel(values, linear: linear), edits: .init(adjustments: adjustments)), linear: linear)
    }
    @Test func neutralKeepsOriginalHDRAndExposureHasRealEVMeaning() throws {
        let source = pixel([4, 2, 1, 1], linear: true)
        let values = sample(try ColorPipeline.grade(source, edits: .init(), sourceHeadroom: 4), linear: true)
        #expect(abs(values[0] - 4) < 0.005)
        let bright = try tune([0.18, 0.18, 0.18, 1], .exposure, 1, linear: true)
        #expect(abs(bright[0] - 0.36) < 0.008)
        let dark = try tune([0.18, 0.18, 0.18, 1], .exposure, -1, linear: true)
        #expect(abs(dark[0] - 0.09) < 0.008)
    }
    @Test func detailFiltersActuallyModifyTextureAndPreserveOpaqueExtent() throws {
        let width = 64, height = 48
        var values: [Float] = []
        for y in 0..<height { for x in 0..<width {
            let value: Float = (x + y) % 2 == 0 ? 0.53 : 0.47
            values += [value, value, value, 1]
        } }
        let source = CIImage(bitmapData: values.withUnsafeBytes { Data($0) }, bytesPerRow: width * 16,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: ColorPipeline.outputSpace)
        for p in [AdjustmentParameter.definition, .sharpness, .noiseReduction] {
            var a = BasicAdjustments(); a[p] = 80
            let result = try BasicColorPipeline.image(source, adjustments: a)
            let original = sample(source, x: 30, y: 20), changed = sample(result, x: 30, y: 20)
            #expect(result.extent == source.extent && abs(changed[3] - 1) < 0.005)
            let originalContrast = abs(original[0] - sample(source, x: 31, y: 20)[0])
            let changedContrast = abs(changed[0] - sample(result, x: 31, y: 20)[0])
            if p == .noiseReduction { #expect(changedContrast < originalContrast - 0.005) }
            else { #expect(changedContrast > originalContrast + 0.005) }
        }
    }
    @Test func histogramCountsDisplayRGBWithoutTransparentPadding() {
        let image = pixel([0.2, 0.4, 0.8, 1]).transformed(by: .init(scaleX: 100, y: 60))
        let histogram = PreviewHistogram.analyze(image)
        #expect(histogram.channels.count == 3)
        for (index, value) in [0.2, 0.4, 0.8].enumerated() {
            let bins = histogram.channels[index]
            let peak = bins.enumerated().max { $0.element < $1.element }?.offset ?? -1
            #expect(abs(peak - Int(value * 255) / 4) <= 1)
            #expect(abs(bins.reduce(0, +) - 1) < 0.01)
        }
    }
    @Test func highlightsAndShadowsAffectTheirOwnTonalRegions() throws {
        let shadow = try tune([0.1, 0.1, 0.1, 1], .shadows, 40)
        let lit = try tune([0.8, 0.8, 0.8, 1], .shadows, 40)
        #expect(shadow[0] > 0.16)
        #expect(abs(lit[0] - 0.8) < 0.01)
        let highlight = try tune([0.9, 0.9, 0.9, 1], .highlights, -40)
        let dim = try tune([0.1, 0.1, 0.1, 1], .highlights, -40)
        #expect(highlight[0] < 0.84)
        #expect(abs(dim[0] - 0.1) < 0.01)
        let black = try tune([0.05, 0.05, 0.05, 1], .blackPoint, 30)
        #expect(black[0] < 0.03)
    }
    @Test func relativeWhiteBalanceAndMonochromeHaveExpectedDirection() throws {
        let warm = try tune([0.5, 0.5, 0.5, 1], .warmth, 50)
        #expect(warm[0] > warm[1] && warm[1] > warm[2])
        let green = try tune([0.5, 0.5, 0.5, 1], .tint, -50)
        #expect(green[1] > green[0] && green[1] > green[2])
        let gray = try tune([0.2, 0.4, 0.7, 1], .saturation, -100)
        #expect(abs(gray[0] - gray[1]) < 0.005 && abs(gray[1] - gray[2]) < 0.005)
    }
    @Test func vignetteDarkensEdgesAndNeverChangesAlpha() throws {
        let input = CIImage(color: CIColor(red: 0.7, green: 0.7, blue: 0.7)).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 100))
        var a = BasicAdjustments(); a.vignette = 80
        let result = try BasicColorPipeline.image(input, adjustments: a)
        let center = sample(result, x: 80, y: 50), edge = sample(result, x: 1, y: 1)
        #expect(edge[0] < center[0] - 0.03)
        #expect(abs(edge[3] - 1) < 0.005 && abs(center[3] - 1) < 0.005)
    }
    @Test func adjustmentsAndRecipesRejectInvalidValuesAndRoundTrip() throws {
        var a = BasicAdjustments(); a[.exposure] = 99; a[.tint] = .nan; a[.sharpness] = -50
        #expect(a.exposure == 4 && a.tint == 0 && a.sharpness == 0)
        var recipe = EditRecipe(); recipe.adjustments = a
        recipe.clip = .init(start: 2, end: 8, cover: 5, speed: 2)
        try recipe.validate()
        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(EditRecipe.self, from: data) == recipe)
        recipe.adjustments.exposure = 99
        #expect(throws: (any Error).self) { try recipe.validate() }
    }
}

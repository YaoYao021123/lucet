import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A deliberately modest SDR-derived look, not recovered camera highlights.
/// Scale RGB together using luminance, preserving hue and midtone exposure.
public enum HDRExpansion {
    private static let kernel: CIColorKernel? = {
        let source = """
        #include <CoreImage/CoreImage.h>
        using namespace metal;
        [[stitchable]] float4 expandHighlight(coreimage::sample_t pixel) {
            float luma = dot(pixel.rgb, float3(0.2126, 0.7152, 0.0722));
            float t = smoothstep(0.55, 1.0, luma);
            return float4(pixel.rgb * (1.0 + t * t), pixel.a);
        }
        """
        return (try? CIKernel.kernels(withMetalString: source))?.first as? CIColorKernel
    }()
    public static func image(_ sdr: CIImage) throws -> CIImage {
        guard let kernel, let result = kernel.apply(extent: sdr.extent, arguments: [sdr]) else {
            throw VideoWorkError.failed("HDR 高光扩展不可用")
        }
        return result
    }
    /// HEIC with an SDR base and generated gain map, plus Apple's Live pairing ID.
    public static func writeCover(_ hdr: CIImage, identifier: String, to url: URL) throws {
        let headroom = max(1, hdr.contentHeadroom)
        let base = ColorPipeline.toneMap(hdr, sourceHeadroom: headroom)
        let context = ColorPipeline.context()
        guard let data = context.heifRepresentation(of: base, format: .RGBA8, colorSpace: ColorPipeline.outputSpace,
                  options: [.hdrImage: hdr]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw StraighteningError.renderFailed
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        var copied = false
        for type in [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap] {
            if let auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) {
                CGImageDestinationAddAuxiliaryDataInfo(destination, type, auxiliary)
                copied = true
            }
        }
        guard copied, CGImageDestinationFinalize(destination) else {
            throw VideoWorkError.failed("HDR 封面增益图写入失败")
        }
        let decoded = try ImageGradeSession.decode(url)
        guard decoded.contentHeadroom > 1 else { throw VideoWorkError.failed("HDR 封面未保留亮度范围") }
    }
}

import CoreImage
import Foundation

public enum AdjustmentGroup: String, CaseIterable, Codable, Sendable {
    case light = "光线", color = "色彩", detail = "细节"
}

/// Relative controls for rendered images/video, not RAW sensor development.
public struct BasicAdjustments: Codable, Equatable, Sendable {
    public var exposure = 0.0
    public var brilliance = 0.0
    public var highlights = 0.0
    public var shadows = 0.0
    public var brightness = 0.0
    public var contrast = 0.0
    public var whites = 0.0
    public var blackPoint = 0.0
    public var warmth = 0.0
    public var tint = 0.0
    public var saturation = 0.0
    public var vibrance = 0.0
    public var definition = 0.0
    public var sharpness = 0.0
    public var noiseReduction = 0.0
    public var vignette = 0.0
    public init() {}
    public subscript(parameter: AdjustmentParameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = newValue.isFinite ? min(parameter.range.upperBound, max(parameter.range.lowerBound, newValue)) : 0 }
    }
    public var sanitized: Self {
        var result = self
        for p in AdjustmentParameter.allCases { result[p] = self[p] }
        return result
    }
    public var isNeutral: Bool { self == Self() }
    public var dictionary: [String: Double] {
        Dictionary(uniqueKeysWithValues: AdjustmentParameter.allCases.map { ($0.rawValue, sanitized[$0]) })
    }
}

public enum AdjustmentParameter: String, CaseIterable, Codable, Sendable, Identifiable {
    case exposure, brilliance, highlights, shadows, brightness, contrast, whites, blackPoint
    case warmth, tint, saturation, vibrance, definition, sharpness, noiseReduction, vignette
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .exposure: "曝光"; case .brilliance: "鲜明度"; case .highlights: "高光"; case .shadows: "阴影"
        case .brightness: "亮度"; case .contrast: "对比度"; case .whites: "白色"; case .blackPoint: "黑点"
        case .warmth: "色温"; case .tint: "色调"; case .saturation: "饱和度"; case .vibrance: "自然饱和度"
        case .definition: "清晰度"; case .sharpness: "锐度"; case .noiseReduction: "降噪"; case .vignette: "晕影"
        }
    }
    public var group: AdjustmentGroup {
        switch self {
        case .exposure, .brilliance, .highlights, .shadows, .brightness, .contrast, .whites, .blackPoint: .light
        case .warmth, .tint, .saturation, .vibrance: .color
        default: .detail
        }
    }
    public var range: ClosedRange<Double> { self == .exposure ? -4...4 : group == .detail ? 0...100 : -100...100 }
    public var keyPath: WritableKeyPath<BasicAdjustments, Double> {
        switch self {
        case .exposure: \.exposure; case .brilliance: \.brilliance; case .highlights: \.highlights; case .shadows: \.shadows
        case .brightness: \.brightness; case .contrast: \.contrast; case .whites: \.whites; case .blackPoint: \.blackPoint
        case .warmth: \.warmth; case .tint: \.tint; case .saturation: \.saturation; case .vibrance: \.vibrance
        case .definition: \.definition; case .sharpness: \.sharpness; case .noiseReduction: \.noiseReduction; case .vignette: \.vignette
        }
    }
    public var explanation: String {
        switch self {
        case .exposure: "整体增加或减少曝光，以 EV 表示；+1 EV 将线性亮度加倍。过曝丢失的细节无法靠此恢复。"
        case .brilliance: "平衡暗部、中间调与亮部。正值提亮暗部并收住高光；这是本地算法，不等同于苹果的空间自适应鲜明度。"
        case .highlights: "调整较亮区域；负值压低高光，尽量减少对暗部的影响。"
        case .shadows: "调整较暗区域；正值提亮阴影，可能同时显露噪点。"
        case .brightness: "调整整体显示亮度。与按倍数改变线性亮度的曝光不同。"
        case .contrast: "拉开或收拢明暗差距。过高会损失暗部与亮部层次。"
        case .whites: "调整接近白色的区域；正值提高白色端，负值压低白色端。"
        case .blackPoint: "调整黑色端；正值加深黑色，负值抬起黑色。"
        case .warmth: "相对白平衡：正值偏暖，负值偏冷。这里是处理后素材的相对偏移，不是相机拍摄 Kelvin 值。"
        case .tint: "相对白平衡：正值偏洋红，负值偏绿色，用于校正或创作色偏。"
        case .saturation: "整体颜色强度。-100 变为灰度；过高容易造成颜色溢出。"
        case .vibrance: "优先增强较不鲜艳的颜色，减少对已经鲜艳颜色的影响；不包含专用肤色保护模型。"
        case .definition: "增强较大范围的局部反差；过高可能出现边缘光晕。"
        case .sharpness: "增强细小边缘反差，不能恢复失焦时丢失的真实细节。"
        case .noiseReduction: "使用单帧降噪；数值越大画面越平滑。视频不使用时序降噪，强度过大可能丢失纹理。"
        case .vignette: "逐渐压暗画面边缘，引导注意力到中央。"
        }
    }
}

public enum BasicColorPipeline {
    private static let encodedSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)!
    private static let kernel: CIColorKernel? = {
        let code = """
        #include <CoreImage/CoreImage.h>
        using namespace metal;
        [[stitchable]] float4 adjustColor(coreimage::sample_t pixel, float4 light, float4 ends, float4 color) {
            float3 rgb = pixel.rgb;
            float y = dot(rgb, float3(0.2126, 0.7152, 0.0722));
            float hi = smoothstep(0.45, 0.95, y);
            float sh = 1.0 - smoothstep(0.04, 0.60, y);
            float white = smoothstep(0.70, 1.0, y);
            float black = 1.0 - smoothstep(0.0, 0.25, y);
            float brilliance = light.x * (0.14 * sh * (1.0 - black) + 0.07 * (1.0 - hi) - 0.12 * hi);
            float target = y + brilliance + light.y * 0.20 + ends.x * 0.22 * hi + ends.y * 0.22 * sh
                + ends.z * 0.16 * white - ends.w * 0.12 * black;
            target = (target - 0.5) * (1.0 + light.z * 0.65) + 0.5;
            target = clamp(target, 0.0, 1.0);
            rgb = y > 0.0001 ? rgb * (target / y) : float3(target);
            rgb *= float3(1.0 + color.x * 0.16 + color.y * 0.04, 1.0 - color.y * 0.12,
                          1.0 - color.x * 0.16 + color.y * 0.04);
            float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
            float chroma = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b));
            float saturation = max(0.0, 1.0 + color.z + color.w * (1.0 - smoothstep(0.15, 0.80, chroma)) * 0.7);
            rgb = float3(luma) + (rgb - float3(luma)) * saturation;
            return float4(max(rgb, float3(0.0)), pixel.a);
        }
        """
        return (try? CIKernel.kernels(withMetalString: code))?.first as? CIColorKernel
    }()
    public static func image(_ source: CIImage, adjustments: BasicAdjustments) throws -> CIImage {
        let a = adjustments.sanitized
        guard !a.isNeutral else { return source }
        var input = source
        if a.exposure != 0 { input = input.applyingFilter("CIExposureAdjust", parameters: ["inputEV": a.exposure]) }
        guard let encoded = input.matchedFromWorkingSpace(to: encodedSpace), let kernel,
              let tuned = kernel.apply(extent: input.extent, arguments: [encoded,
                CIVector(x: a.brilliance / 100, y: a.brightness / 100, z: a.contrast / 100, w: 0),
                CIVector(x: a.highlights / 100, y: a.shadows / 100, z: a.whites / 100, w: a.blackPoint / 100),
                CIVector(x: a.warmth / 100, y: a.tint / 100, z: a.saturation / 100, w: a.vibrance / 100)]),
              var result = tuned.matchedToWorkingSpace(from: encodedSpace) else {
            throw VideoWorkError.failed("基础调色滤镜不可用，未应用调整。")
        }
        let scale = max(source.extent.width, source.extent.height) / 1600
        if a.noiseReduction > 0 {
            result = result.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": a.noiseReduction / 100 * 0.06, "inputSharpness": 0])
        }
        if a.definition > 0 {
            result = result.clampedToExtent().applyingFilter("CIUnsharpMask", parameters: ["inputRadius": max(1, 8 * scale), "inputIntensity": a.definition / 100 * 0.7]).cropped(to: source.extent)
        }
        if a.sharpness > 0 {
            result = result.clampedToExtent().applyingFilter("CIUnsharpMask", parameters: ["inputRadius": max(0.5, 1.2 * scale), "inputIntensity": a.sharpness / 100 * 1.2]).cropped(to: source.extent)
        }
        if a.vignette > 0 {
            result = result.applyingFilter("CIVignetteEffect", parameters: ["inputCenter": CIVector(x: source.extent.midX, y: source.extent.midY),
                "inputRadius": min(source.extent.width, source.extent.height) * 0.55, "inputIntensity": a.vignette / 100 * 1.5, "inputFalloff": 1])
        }
        return result.cropped(to: source.extent)
    }
}

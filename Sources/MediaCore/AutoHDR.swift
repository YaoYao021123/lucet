import Accelerate
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// "AI HDR": turns an ordinary (SDR) photo into an HDR one by predicting, for every spot, how many
/// stops brighter it may glow on an HDR screen. The network is GMNet (Liao et al., "Learning Gain Map
/// for Inverse Tone Mapping", ICLR 2025; MIT, github.com/qtlark/GMNet), real-world checkpoint. A
/// global branch reads the whole picture at 256 × 256; a local branch predicts the gain map. The
/// gain (0…log2 5 stops) multiplies the edited picture in linear light, so the SDR look is unchanged
/// and HDR screens get the extra light. Weights: assets/models/gmnet-realworld.bin
/// (scripts/convert-gmnet.py). Runs on the Mac with Accelerate.
public final class AutoHDR: Sendable {
    /// The most a spot is brightened, in stops (the model's real-world range).
    public static let maxStops = log2(5.0)
    /// Long side of the picture the local branch sees; the gain map is smooth, so this is plenty.
    public static let workingSize = 1024

    struct Conv {
        let input: Int, output: Int, kernel: Int
        let weight: [Float]   // [output][input][kernel][kernel]
        let bias: [Float]
    }

    /// Channels × height × width, row-major, top row first.
    struct Map {
        var channels: Int, height: Int, width: Int
        var data: [Float]
        var plane: Int { height * width }
    }

    private let convs: [String: Conv]

    public static let shared: AutoHDR? = {
        let name = "gmnet-realworld.bin"
        var places: [URL] = []
        if let url = Bundle.main.url(forResource: "gmnet-realworld", withExtension: "bin") { places.append(url) }
        if let executable = Bundle.main.executableURL { places.append(executable.deletingLastPathComponent().appendingPathComponent(name)) }
        places.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../assets/models/\(name)").standardized)
        for place in places where FileManager.default.fileExists(atPath: place.path) {
            if let model = try? AutoHDR(contentsOf: place) { return model }
        }
        return nil
    }()

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let damaged = VideoWorkError.failed(L("AI HDR 模型文件已损坏。"))
        guard data.count > 12, data.prefix(4) == Data("GMNT".utf8) else { throw damaged }
        func uint32(_ at: Int) -> Int { Int(UInt32(littleEndian: data[at..<(at + 4)].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })) }
        guard uint32(4) == 1 else { throw damaged }
        let headerLength = uint32(8)
        guard 12 + headerLength <= data.count else { throw damaged }
        struct Entry: Decodable { let name: String; let shape: [Int]; let offset: Int }
        let entries = try JSONDecoder().decode([Entry].self, from: data[12..<(12 + headerLength)])
        let start = 12 + headerLength
        var tensors: [String: (shape: [Int], values: [Float])] = [:]
        for entry in entries {
            let count = entry.shape.reduce(1, *)
            let from = start + entry.offset * 4
            guard count > 0, from + count * 4 <= data.count else { throw damaged }
            var values = [Float](repeating: 0, count: count)
            values.withUnsafeMutableBytes { _ = data.copyBytes(to: $0, from: from..<(from + count * 4)) }
            tensors[entry.name] = (entry.shape, values)
        }
        var convs: [String: Conv] = [:]
        for (name, tensor) in tensors where name.hasSuffix(".weight") {
            let base = String(name.dropLast(".weight".count))
            guard tensor.shape.count == 4, let bias = tensors[base + ".bias"], bias.values.count == tensor.shape[0] else { throw damaged }
            convs[base] = Conv(input: tensor.shape[1], output: tensor.shape[0], kernel: tensor.shape[2], weight: tensor.values, bias: bias.values)
        }
        // The layers the network needs, checked once so inference never meets a missing one.
        let needed = ["down1.conv.0", "down2.conv.4", "res_y.4.conv2", "sq_ker.conv.4", "sq_chn.conv.4", "sq_qmax.conv.4",
                      "mask_est.0", "mask_est.2", "down_x.conv.4", "res1.4.conv2", "res2.4.conv2", "res3.4.conv2", "upconv", "HRconv", "conv_last"]
        guard needed.allSatisfy({ convs[$0] != nil }) else { throw damaged }
        self.convs = convs
    }

    // MARK: Layers

    private func conv(_ x: Map, _ name: String, stride: Int = 1) -> Map {
        let c = convs[name]!
        precondition(c.input == x.channels)
        let k = c.kernel, pad = k / 2
        let oh = (x.height + 2 * pad - k) / stride + 1, ow = (x.width + 2 * pad - k) / stride + 1
        var out = Map(channels: c.output, height: oh, width: ow, data: [Float](repeating: 0, count: c.output * oh * ow))
        let depth = c.input * k * k
        // Output rows are done in bands so the unfolded input stays small (≈ 16 MB).
        let bandRows = max(1, min(oh, 4_000_000 / max(1, depth * ow)))
        var columns = [Float](repeating: 0, count: depth * bandRows * ow)
        var band = [Float](repeating: 0, count: c.output * bandRows * ow)
        x.data.withUnsafeBufferPointer { src in
            columns.withUnsafeMutableBufferPointer { cols in
                band.withUnsafeMutableBufferPointer { result in
                    out.data.withUnsafeMutableBufferPointer { dst in
                        c.weight.withUnsafeBufferPointer { weights in
                            var y0 = 0
                            while y0 < oh {
                                let rows = min(bandRows, oh - y0), n = rows * ow
                                vDSP_vclr(cols.baseAddress!, 1, vDSP_Length(depth * n))
                                for ci in 0..<c.input { for ky in 0..<k { for kx in 0..<k {
                                    let row = ((ci * k + ky) * k + kx) * n
                                    // Output columns whose input pixel is inside the picture.
                                    let first = max(0, (pad - kx + stride - 1) / stride)
                                    let last = min(ow - 1, (x.width - 1 + pad - kx) / stride)
                                    guard last >= first else { continue }
                                    for oy in y0..<(y0 + rows) {
                                        let iy = oy * stride - pad + ky
                                        guard iy >= 0, iy < x.height else { continue }
                                        cblas_scopy(Int32(last - first + 1), src.baseAddress! + ci * x.plane + iy * x.width + first * stride - pad + kx,
                                                    Int32(stride), cols.baseAddress! + row + (oy - y0) * ow + first, 1)
                                    }
                                } } }
                                cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(c.output), Int32(n), Int32(depth),
                                            1, weights.baseAddress!, Int32(depth), cols.baseAddress!, Int32(n), 0, result.baseAddress!, Int32(n))
                                for o in 0..<c.output {
                                    var b = c.bias[o]
                                    vDSP_vsadd(result.baseAddress! + o * n, 1, &b, dst.baseAddress! + o * oh * ow + y0 * ow, 1, vDSP_Length(n))
                                }
                                y0 += rows
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    private func relu(_ m: inout Map) {
        var zero: Float = 0
        m.data.withUnsafeMutableBufferPointer { vDSP_vthres($0.baseAddress!, 1, &zero, $0.baseAddress!, 1, vDSP_Length($0.count)) }
    }

    private func sigmoid(_ values: inout [Float]) {
        var minusOne: Float = -1, one: Float = 1, count = Int32(values.count)
        values.withUnsafeMutableBufferPointer { p in
            vDSP_vsmul(p.baseAddress!, 1, &minusOne, p.baseAddress!, 1, vDSP_Length(p.count))
            vvexpf(p.baseAddress!, p.baseAddress!, &count)
            vDSP_vsadd(p.baseAddress!, 1, &one, p.baseAddress!, 1, vDSP_Length(p.count))
            vvrecf(p.baseAddress!, p.baseAddress!, &count)
        }
    }

    /// Conv (stride 2) – ReLU – conv – ReLU – conv – ReLU.
    private func down(_ x: Map, _ prefix: String) -> Map {
        var y = conv(x, prefix + ".conv.0", stride: 2); relu(&y)
        y = conv(y, prefix + ".conv.2"); relu(&y)
        y = conv(y, prefix + ".conv.4"); relu(&y)
        return y
    }

    /// Residual blocks without batch norm: x + conv2(ReLU(conv1(x))).
    private func residual(_ x: Map, _ prefix: String, blocks: Int = 5) -> Map {
        var x = x
        for i in 0..<blocks {
            var y = conv(x, "\(prefix).\(i).conv1"); relu(&y)
            let z = conv(y, "\(prefix).\(i).conv2")
            x.data.withUnsafeMutableBufferPointer { p in vDSP_vadd(p.baseAddress!, 1, z.data, 1, p.baseAddress!, 1, vDSP_Length(p.count)) }
        }
        return x
    }

    /// Adaptive average pooling to size × size (PyTorch's uneven bins), then three 1 × 1 convolutions.
    private func squeeze(_ y: Map, _ prefix: String, size: Int) -> Map {
        var pooled = Map(channels: y.channels, height: size, width: size, data: [Float](repeating: 0, count: y.channels * size * size))
        for c in 0..<y.channels { for by in 0..<size { for bx in 0..<size {
            let y0 = by * y.height / size, y1 = ((by + 1) * y.height + size - 1) / size
            let x0 = bx * y.width / size, x1 = ((bx + 1) * y.width + size - 1) / size
            var sum: Float = 0
            for row in y0..<y1 { for col in x0..<x1 { sum += y.data[c * y.plane + row * y.width + col] } }
            pooled.data[c * size * size + by * size + bx] = sum / Float((y1 - y0) * (x1 - x0))
        } } }
        var a = conv(pooled, prefix + ".conv.0"); relu(&a)
        a = conv(a, prefix + ".conv.2"); relu(&a)
        return conv(a, prefix + ".conv.4")
    }

    /// Each channel filtered with its own predicted 3 × 3 kernel (zero padding).
    private func depthwise(_ x: Map, kernel: [Float]) -> Map {
        var out = Map(channels: x.channels, height: x.height, width: x.width, data: [Float](repeating: 0, count: x.data.count))
        x.data.withUnsafeBufferPointer { src in
            out.data.withUnsafeMutableBufferPointer { dst in
                for c in 0..<x.channels { for ky in 0..<3 { for kx in 0..<3 {
                    var w = kernel[c * 9 + ky * 3 + kx]
                    let dx = kx - 1, first = max(0, -dx), last = min(x.width - 1, x.width - 1 - dx)
                    for oy in 0..<x.height {
                        let iy = oy + ky - 1
                        guard iy >= 0, iy < x.height else { continue }
                        let to = dst.baseAddress! + c * x.plane + oy * x.width + first
                        vDSP_vsma(src.baseAddress! + c * x.plane + iy * x.width + first + dx, 1, &w, to, 1, to, 1, vDSP_Length(last - first + 1))
                    }
                } } }
            }
        }
        return out
    }

    /// PixelShuffle(2): 4C × H × W → C × 2H × 2W.
    private func shuffle(_ x: Map) -> Map {
        let c = x.channels / 4, h = x.height * 2, w = x.width * 2
        var out = Map(channels: c, height: h, width: w, data: [Float](repeating: 0, count: c * h * w))
        for ch in 0..<c { for i in 0..<2 { for j in 0..<2 {
            let source = (ch * 4 + i * 2 + j) * x.plane
            for y in 0..<x.height { for xx in 0..<x.width {
                out.data[ch * h * w + (y * 2 + i) * w + xx * 2 + j] = x.data[source + y * x.width + xx]
            } }
        } } }
        return out
    }

    // MARK: Network

    /// The gain map in stops for a picture: `global` is 3 × 256 × 256 and `local` 3 × H × W, both sRGB
    /// 0…1. Returns 1 × H × W values in 0…maxStops (H and W even).
    func gainMap(global: Map, local: Map) -> Map {
        var (out, qmax) = network(global: global, local: local)
        // The real-world model predicts gain / log2(5), scaled by its own qmax.
        var scale = qmax * Float(Self.maxStops), low: Float = 0, high = Float(Self.maxStops)
        out.data.withUnsafeMutableBufferPointer { p in
            vDSP_vsmul(p.baseAddress!, 1, &scale, p.baseAddress!, 1, vDSP_Length(p.count))
            vDSP_vclip(p.baseAddress!, 1, &low, &high, p.baseAddress!, 1, vDSP_Length(p.count))
        }
        return out
    }

    /// GMNet's forward pass as published: the local output and the global qmax. The full-size
    /// tail runs `tailRows` rows of the half-size features at a time (the result is the same).
    func network(global: Map, local: Map, tailRows: Int = 48) -> (out: Map, qmax: Float) {
        var y = down(global, "down1")
        y = down(y, "down2")
        y = residual(y, "res_y")
        let kernel = squeeze(y, "sq_ker", size: 3).data
        var channelWeights = squeeze(y, "sq_chn", size: 1).data
        sigmoid(&channelWeights)
        let qmax = squeeze(y, "sq_qmax", size: 1).data[0]

        var x = down(local, "down_x")
        x = residual(x, "res1")
        var mask = conv(depthwise(x, kernel: kernel), "mask_est.0"); relu(&mask)
        mask = conv(mask, "mask_est.2")
        sigmoid(&mask.data)
        let plane = x.plane
        x.data.withUnsafeMutableBufferPointer { p in
            for c in 0..<x.channels {
                vDSP_vmul(p.baseAddress! + c * plane, 1, mask.data, 1, p.baseAddress! + c * plane, 1, vDSP_Length(plane))
            }
        }
        x = residual(x, "res2")
        x.data.withUnsafeMutableBufferPointer { p in
            for c in 0..<channelWeights.count {
                vDSP_vsmul(p.baseAddress! + c * plane, 1, &channelWeights[c], p.baseAddress! + c * plane, 1, vDSP_Length(plane))
            }
        }
        x = residual(x, "res3")
        return (tail(x, rows: tailRows), qmax)
    }

    /// upconv → PixelShuffle(2) → ReLU → HRconv → ReLU → conv_last, in bands of rows so the
    /// full-size 64-channel maps never exist all at once. Each band reads two extra rows on either
    /// side: three 3 × 3 convolutions reach that far, so the rows kept are exact.
    private func tail(_ x: Map, rows band: Int) -> Map {
        let halo = 2
        var out = Map(channels: 1, height: x.height * 2, width: x.width * 2, data: [Float](repeating: 0, count: x.plane * 4))
        var r0 = 0
        while r0 < x.height {
            let r1 = min(x.height, r0 + max(1, band))
            let s0 = max(0, r0 - halo), s1 = min(x.height, r1 + halo)
            var slice = Map(channels: x.channels, height: s1 - s0, width: x.width, data: [])
            slice.data.reserveCapacity(x.channels * slice.plane)
            for c in 0..<x.channels { slice.data += x.data[(c * x.plane + s0 * x.width)..<(c * x.plane + s1 * x.width)] }
            var up = shuffle(conv(slice, "upconv")); relu(&up)
            var hr = conv(up, "HRconv"); relu(&hr)
            let part = conv(hr, "conv_last")
            let from = 2 * (r0 - s0) * part.width, count = 2 * (r1 - r0) * part.width
            out.data.replaceSubrange((2 * r0 * out.width)..<(2 * r0 * out.width + count), with: part.data[from..<(from + count)])
            r0 = r1
        }
        return out
    }

    // MARK: Photos

    private final class Entry { let gain: CIImage?; init(_ gain: CIImage?) { self.gain = gain } }
    nonisolated(unsafe) private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>(); cache.countLimit = 12; return cache
    }()

    private static func key(_ url: URL) -> NSString {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)#\(modified)" as NSString
    }

    /// The predicted gain map (stops, single channel) of an upright photo, origin at the bottom
    /// left, computed once per photo. Nil if the photo can't be read.
    public func gain(for url: URL) -> CIImage? {
        let key = Self.key(url)
        if let hit = Self.cache.object(forKey: key) { return hit.gain }
        let result = compute(url)
        Self.cache.setObject(Entry(result), forKey: key)
        return result
    }

    private func compute(_ url: URL) -> CIImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: Self.workingSize]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // Even sizes, so the 2× down-and-up path lands on the same size.
        let width = max(2, image.width / 2 * 2), height = max(2, image.height / 2 * 2)
        guard let local = Self.planar(image, width: width, height: height), let global = Self.planar(image, width: 256, height: 256) else { return nil }
        let gain = gainMap(global: global, local: local)
        let bytes = gain.data.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: bytes, bytesPerRow: gain.width * 4, size: CGSize(width: gain.width, height: gain.height),
                       format: .Rf, colorSpace: nil)
    }

    /// sRGB planes 0…1 at a size (stretched, as the model was fed).
    static func planar(_ image: CGImage, width: Int, height: Int) -> Map? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let plane = width * height
        var values = [Float](repeating: 0, count: 3 * plane)
        for i in 0..<plane { for c in 0..<3 { values[c * plane + i] = Float(bytes[i * 4 + c]) / 255 } }
        return Map(channels: 3, height: height, width: width, data: values)
    }
}

extension ColorPipeline {
    private static let boostKernel: CIColorKernel? = {
        let code = """
        #include <CoreImage/CoreImage.h>
        using namespace metal;
        [[stitchable]] float4 hdrBoost(coreimage::sample_t p, coreimage::sample_t g, float amount) {
            return float4(p.rgb * exp2(max(g.r, 0.0) * amount), p.a);
        }
        """
        return (try? CIKernel.kernels(withMetalString: code))?.first as? CIColorKernel
    }()

    /// The AI HDR glow on top of a graded picture (before rotation and crop), in linear light.
    /// Unchanged when the effect is off, there's no model, or the photo file isn't known.
    public static func applyHDR(_ image: CIImage, edits: MediaEdits) -> CIImage {
        guard edits.hdrAmount > 0, let url = edits.source, let model = AutoHDR.shared, let gain = model.gain(for: url),
              let kernel = boostKernel, !image.extent.isInfinite, gain.extent.width > 0, gain.extent.height > 0 else { return image }
        let extent = image.extent
        let fitted = gain.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / gain.extent.width, y: extent.height / gain.extent.height))
            .clampedToExtent()
        return kernel.apply(extent: extent, arguments: [image, fitted, Float(edits.hdrAmount)])?.cropped(to: extent) ?? image
    }

    /// How bright the AI HDR glow can get (for display headroom).
    public static func hdrHeadroom(_ edits: MediaEdits) -> Float {
        edits.hdrAmount > 0 && AutoHDR.shared != nil ? Float(exp2(AutoHDR.maxStops * edits.hdrAmount)) : 1
    }
}

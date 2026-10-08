import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageExportOptions: Codable, Equatable, Sendable {
    public enum Format: String, Codable, CaseIterable, Sendable {
        case jpeg, heic, png
        public var title: String { switch self { case .jpeg: "JPEG"; case .heic: "HEIC"; case .png: "PNG" } }
        public var fileExtension: String { switch self { case .jpeg: "jpg"; case .heic: "heic"; case .png: "png" } }
        public var type: UTType { switch self { case .jpeg: .jpeg; case .heic: .heic; case .png: .png } }
        public var isLossy: Bool { self != .png }
    }
    public var format: Format = .jpeg
    /// 0...1, used by JPEG and HEIC.
    public var quality: Double = 0.9
    /// Longest output edge in pixels; nil keeps the edited size.
    public var maxLongEdge: Int?
    /// Copy capture date, camera, lens and exposure data from the original.
    public var keepMetadata = true
    /// Drop GPS data even when other metadata is kept.
    public var removeLocation = true
    public init() {}
}

public enum ImageExporter {
    /// Writes a new file. Refuses the source path; refuses other existing files
    /// unless `allowReplacing` is set (the user confirmed in a save panel).
    public static func export(_ url: URL, to output: URL, edits: MediaEdits, options: ImageExportOptions,
                              allowReplacing: Bool = false) throws {
        try Task.checkCancellation()
        guard output.isFileURL, output.standardizedFileURL != url.standardizedFileURL else { throw VideoWorkError.outputExists }
        guard output.pathExtension.lowercased() == options.format.fileExtension
                || (options.format == .jpeg && output.pathExtension.lowercased() == "jpeg") else {
            throw VideoWorkError.failed("文件扩展名需与导出格式 \(options.format.title) 一致。")
        }
        if !allowReplacing, FileManager.default.fileExists(atPath: output.path) { throw VideoWorkError.outputExists }
        let input = try ImageGradeSession.decode(url)
        let headroom = max(1, input.contentHeadroom)
        let graded = try ColorPipeline.grade(input, edits: edits, sourceHeadroom: headroom)
        var transformed = try ColorPipeline.geometry(graded, edits: edits)
        if let limit = options.maxLongEdge, limit >= 16 {
            let longEdge = max(transformed.extent.width, transformed.extent.height)
            if longEdge > CGFloat(limit) {
                let scale = CGFloat(limit) / longEdge
                transformed = transformed.applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1
                ])
                transformed = transformed.cropped(to: CGRect(x: transformed.extent.minX, y: transformed.extent.minY,
                    width: floor(transformed.extent.width), height: floor(transformed.extent.height)))
            }
        }
        try Task.checkCancellation()
        let bitmap = try ColorPipeline.sdrBitmap(transformed, headroom: edits.hasGrade ? 1 : headroom)
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if options.keepMetadata { properties.merge(metadata(of: url, removeLocation: options.removeLocation,
                                                            width: bitmap.width, height: bitmap.height)) { _, new in new } }
        if options.format.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.1, options.quality)) }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, options.format.type.identifier as CFString, 1, nil) else {
            throw VideoWorkError.failed("系统不支持写入 \(options.format.title)。")
        }
        CGImageDestinationAddImage(destination, bitmap, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StraighteningError.renderFailed }
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".workbench-\(UUID().uuidString).\(options.format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try (data as Data).write(to: temporary, options: .atomic)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: output.path) {
            guard allowReplacing else { throw VideoWorkError.outputExists }
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: output)
        }
    }

    /// Capture metadata worth keeping. Orientation is already applied to pixels;
    /// Apple maker data is dropped so the export is never mistaken for a Live Photo still.
    static func metadata(of url: URL, removeLocation: Bool, width: Int, height: Int) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [:] }
        var result: [CFString: Any] = [:]
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = width
            exif[kCGImagePropertyExifPixelYDimension] = height
            exif.removeValue(forKey: kCGImagePropertyExifSubjectArea)
            result[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            tiff[kCGImagePropertyTIFFSoftware] = "光集"
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        for key in [kCGImagePropertyIPTCDictionary, kCGImagePropertyExifAuxDictionary] {
            if let value = properties[key] { result[key] = value }
        }
        if !removeLocation, let gps = properties[kCGImagePropertyGPSDictionary] { result[kCGImagePropertyGPSDictionary] = gps }
        return result
    }
}

/// Camera facts shown in the Info panel. All fields are optional.
public struct CaptureInfo: Sendable, Equatable {
    public var camera: String?
    public var lens: String?
    public var focalLength: String?
    public var aperture: String?
    public var shutter: String?
    public var iso: String?
    public var captured: String?
    public var hasLocation = false
    /// The same settings as numbers, for lessons that use the user's own photo.
    public var fNumber: Double?
    public var exposureTime: Double?
    public var isoValue: Int?
    public var focalLengthMM: Double?
    public var focalLength35mm: Double?

    public static func read(_ url: URL) -> CaptureInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var info = CaptureInfo()
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        if let model { info.camera = make.map { model.hasPrefix($0) ? model : "\($0) \(model)" } ?? model }
        info.lens = exif[kCGImagePropertyExifLensModel] as? String
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double { info.focalLength = String(format: "%.0f mm", focal); info.focalLengthMM = focal }
        info.focalLength35mm = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue
        if let f = exif[kCGImagePropertyExifFNumber] as? Double { info.aperture = String(format: "ƒ/%.1f", f); info.fNumber = f }
        if let time = exif[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            info.shutter = time >= 1 ? String(format: "%.1f s", time) : "1/\(Int((1 / time).rounded())) s"
            info.exposureTime = time
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { info.iso = "ISO \(iso)"; info.isoValue = iso }
        info.captured = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        info.hasLocation = properties[kCGImagePropertyGPSDictionary] != nil
        let empty = info.camera == nil && info.lens == nil && info.focalLength == nil && info.aperture == nil
            && info.shutter == nil && info.iso == nil && info.captured == nil
        return empty ? nil : info
    }
}

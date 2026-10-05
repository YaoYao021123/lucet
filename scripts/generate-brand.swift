import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let ink = "33362E", gold = "B6A16B", ivory = "F2F0E8", darkGold = "CDBA83", black = "171915"
let blade = "M66 17 C90 18 110 38 111 62 L86 62 L66 42 Z"
func color(_ hex: String) -> CGColor {
    let n = Int(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
}
func bladePath() -> CGPath {
    let p = CGMutablePath(); p.move(to: CGPoint(x: 66, y: 17))
    p.addCurve(to: CGPoint(x: 111, y: 62), control1: CGPoint(x: 90, y: 18), control2: CGPoint(x: 110, y: 38))
    p.addLine(to: CGPoint(x: 86, y: 62)); p.addLine(to: CGPoint(x: 66, y: 42)); p.closeSubpath(); return p
}
func drawMark(_ ctx: CGContext, rect: CGRect, foreground: String, accent: String) {
    ctx.saveGState(); ctx.translateBy(x: rect.minX, y: rect.minY); ctx.scaleBy(x: rect.width / 128, y: rect.height / 128)
    for i in 0..<4 {
        ctx.saveGState(); ctx.translateBy(x: 64, y: 64); ctx.rotate(by: CGFloat(i) * .pi / 2); ctx.translateBy(x: -64, y: -64)
        ctx.addPath(bladePath()); ctx.setFillColor(color(i == 0 ? accent : foreground)); ctx.fillPath(); ctx.restoreGState()
    }
    ctx.restoreGState()
}
func markSVG(_ foreground: String, _ accent: String) -> String {
    (0..<4).map { "<path d=\"\(blade)\" fill=\"#\($0 == 0 ? accent : foreground)\"\($0 == 0 ? "" : " transform=\"rotate(\($0 * 90) 64 64)\"")/>" }.joined()
}
func svg(_ name: String, width: Int, height: Int, content: String) throws {
    let text = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\" role=\"img\"><title>\(name)</title>\(content)</svg>\n"
    try text.write(to: root.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}
func bitmap(_ name: String, width: Int, height: Int, paint: (CGContext) -> Void) throws {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1); paint(ctx)
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(root.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG export failed") }
}
func textPath(_ text: String, size: CGFloat, x: CGFloat, baseline: CGFloat, tracking: CGFloat = 0, semibold: Bool = false) -> CGPath {
    let font = CTFontCreateWithName((semibold ? "PingFangSC-Semibold" : "PingFangSC-Regular") as CFString, size, nil)
    let chars = Array(text.utf16); var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    precondition(CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count), "Missing brand text glyphs")
    var advances = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
    let result = CGMutablePath(); var pen = x
    for (i, glyph) in glyphs.enumerated() {
        if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
            result.addPath(path, transform: .init(a: 1, b: 0, c: 0, d: -1, tx: pen, ty: baseline))
        }
        pen += advances[i].width + tracking
    }
    return result
}
func pathSVG(_ path: CGPath) -> String {
    var s = ""
    func pt(_ p: CGPoint) -> String { String(format: "%.3f %.3f", Double(p.x), Double(p.y)) }
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: s += "M" + pt(e.points[0])
        case .addLineToPoint: s += "L" + pt(e.points[0])
        case .addQuadCurveToPoint: s += "Q" + pt(e.points[0]) + " " + pt(e.points[1])
        case .addCurveToPoint: s += "C" + pt(e.points[0]) + " " + pt(e.points[1]) + " " + pt(e.points[2])
        case .closeSubpath: s += "Z"
        @unknown default: break
        }
    }
    return s
}
func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, x: CGFloat, baseline: CGFloat, fill: String, semibold: Bool = false) {
    ctx.addPath(textPath(text, size: size, x: x, baseline: baseline, semibold: semibold)); ctx.setFillColor(color(fill)); ctx.fillPath()
}

// Exact source mark; 4 finished adaptations plus outline wordmarks.
try svg("guangji-symbol", width: 128, height: 128, content: markSVG(ink, gold))
try svg("guangji-symbol-dark", width: 128, height: 128, content: markSVG(ivory, darkGold))
try svg("guangji-symbol-mono", width: 128, height: 128, content: markSVG(ink, ink))
try svg("guangji-symbol-white", width: 128, height: 128, content: markSVG("FFFFFF", "FFFFFF"))
for (suffix, fg, accent) in [("", ink, gold), ("-dark", ivory, darkGold), ("-mono", ink, ink)] {
    let letters = textPath("光集", size: 50, x: 145, baseline: 82, tracking: 5, semibold: true)
    try svg("guangji-wordmark" + suffix, width: 300, height: 128,
        content: markSVG(fg, accent) + "<path d=\"\(pathSVG(letters))\" fill=\"#\(fg)\"/>")
    try bitmap("exports/guangji-wordmark" + suffix, width: 900, height: 384) { ctx in
        ctx.scaleBy(x: 3, y: 3); drawMark(ctx, rect: CGRect(x: 0, y: 0, width: 128, height: 128), foreground: fg, accent: accent)
        ctx.addPath(letters); ctx.setFillColor(color(fg)); ctx.fillPath()
    }
}
for (name, fg, accent) in [("light", ink, gold), ("dark", ivory, darkGold), ("mono", ink, ink), ("white", "FFFFFF", "FFFFFF")] {
    try bitmap("exports/guangji-symbol-" + name, width: 1024, height: 1024) { drawMark($0, rect: CGRect(x: 0, y: 0, width: 1024, height: 1024), foreground: fg, accent: accent) }
}
// Layer source remains square/unmasked for later Icon Composer assembly.
try svg("layers/background", width: 1024, height: 1024, content: "<path d=\"M0 0H1024V1024H0Z\" fill=\"#\(black)\"/>")
try svg("layers/aperture-ivory", width: 1024, height: 1024, content: "<g transform=\"translate(164 164) scale(5.4375)\">" + (1..<4).map { "<path d=\"\(blade)\" fill=\"#\(ivory)\" transform=\"rotate(\($0 * 90) 64 64)\"/>" }.joined() + "</g>")
try svg("layers/aperture-gold", width: 1024, height: 1024, content: "<g transform=\"translate(164 164) scale(5.4375)\"><path d=\"\(blade)\" fill=\"#\(darkGold)\"/></g>")
func paintIcon(_ ctx: CGContext, size: Int, light: Bool = false) {
    ctx.saveGState(); ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 196, cornerHeight: 196, transform: nil))
    ctx.setFillColor(color(light ? "F2F0E8" : black)); ctx.fillPath()
    drawMark(ctx, rect: CGRect(x: 164, y: 164, width: 696, height: 696), foreground: light ? ink : ivory, accent: light ? gold : darkGold)
    ctx.restoreGState()
}
try svg("icons/guangji-app-icon", width: 1024, height: 1024, content: "<rect x=\"64\" y=\"64\" width=\"896\" height=\"896\" rx=\"196\" fill=\"#\(black)\"/><g transform=\"translate(164 164) scale(5.4375)\">\(markSVG(ivory, darkGold))</g>")
try bitmap("icons/guangji-app-icon", width: 1024, height: 1024) { paintIcon($0, size: 1024) }
try bitmap("icons/guangji-app-icon-light", width: 1024, height: 1024) { paintIcon($0, size: 1024, light: true) }
let iconset = root.appendingPathComponent("icons/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icons/AppIcon.iconset/icon_\(point)x\(point)" + (scale == 2 ? "@2x" : "")
        try bitmap(name, width: point * scale, height: point * scale) { paintIcon($0, size: point * scale) }
    }
}
// Brand empty state: flat logo, image/video/Live strip; no glass or decorative motion.
func paintEmpty(_ ctx: CGContext, dark: Bool) {
    let fg = dark ? "8C9187" : "73786C", accent = dark ? darkGold : gold
    drawMark(ctx, rect: CGRect(x: 124, y: 0, width: 232, height: 232), foreground: dark ? ivory : ink, accent: accent)
    ctx.setStrokeColor(color(fg)); ctx.setLineWidth(2)
    for i in 0..<3 {
        let rect = CGRect(x: 136 + i * 72, y: 254, width: 64, height: 42)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)); ctx.strokePath()
    }
    ctx.beginPath(); ctx.move(to: CGPoint(x: 145, y: 286)); ctx.addLine(to: CGPoint(x: 157, y: 273)); ctx.addLine(to: CGPoint(x: 168, y: 282)); ctx.addLine(to: CGPoint(x: 181, y: 267)); ctx.addLine(to: CGPoint(x: 192, y: 286)); ctx.strokePath()
    ctx.beginPath(); ctx.move(to: CGPoint(x: 233, y: 265)); ctx.addLine(to: CGPoint(x: 249, y: 275)); ctx.addLine(to: CGPoint(x: 233, y: 285)); ctx.closePath(); ctx.strokePath()
    ctx.strokeEllipse(in: CGRect(x: 303, y: 263, width: 24, height: 24)); ctx.strokeEllipse(in: CGRect(x: 309, y: 269, width: 12, height: 12))
}
for dark in [false, true] {
    let fg = dark ? "8C9187" : "73786C", face = dark ? ivory : ink, accent = dark ? darkGold : gold
    let strip = (0..<3).map { "<rect x=\"\(136 + $0 * 72)\" y=\"254\" width=\"64\" height=\"42\" rx=\"5\"/>" }.joined()
    let glyphs = "<path d=\"M145 286L157 273L168 282L181 267L192 286M233 265L249 275L233 285Z\"/><circle cx=\"315\" cy=\"275\" r=\"12\"/><circle cx=\"315\" cy=\"275\" r=\"6\"/>"
    try svg("illustrations/empty-library-" + (dark ? "dark" : "light"), width: 480, height: 320,
        content: "<g transform=\"translate(124 0) scale(1.8125)\">\(markSVG(face, accent))</g><g fill=\"none\" stroke=\"#\(fg)\" stroke-width=\"2\">\(strip)\(glyphs)</g>")
}
for dark in [false, true] {
    let suffix = dark ? "dark" : "light"
    try bitmap("illustrations/empty-library-" + suffix, width: 960, height: 640) { ctx in ctx.scaleBy(x: 2, y: 2); paintEmpty(ctx, dark: dark) }
    try bitmap("runtime/EmptyLibrary-" + suffix, width: 960, height: 640) { ctx in ctx.scaleBy(x: 2, y: 2); paintEmpty(ctx, dark: dark) }
}
// Main visual: one brand scene, not a UI screenshot or invented product claim.
func paintHero(_ ctx: CGContext, dark: Bool, vertical: Bool = false) {
    ctx.setFillColor(color(dark ? "000000" : "FFFFFF")); ctx.fill(CGRect(x: 0, y: 0, width: vertical ? 1080 : 1920, height: vertical ? 1440 : 1080))
    let fg = dark ? ivory : ink, accent = dark ? darkGold : gold
    let markRect = vertical ? CGRect(x: 210, y: 200, width: 660, height: 660) : CGRect(x: 1060, y: 148, width: 784, height: 784)
    drawMark(ctx, rect: markRect, foreground: fg, accent: accent)
    drawText(ctx, "光集", size: vertical ? 88 : 94, x: vertical ? 96 : 128, baseline: vertical ? 1040 : 460, fill: fg, semibold: true)
    drawText(ctx, "把光，收进画面。", size: vertical ? 36 : 38, x: vertical ? 96 : 130, baseline: vertical ? 1130 : 554, fill: fg)
    drawText(ctx, "调色 · 片段 · Live", size: 25, x: vertical ? 100 : 132, baseline: vertical ? 1225 : 643, fill: accent)
    ctx.setFillColor(color(accent)); ctx.fill(CGRect(x: vertical ? 100 : 132, y: vertical ? 1280 : 716, width: 56, height: 3))
}
func heroSVG(dark: Bool, vertical: Bool = false) throws {
    let w = vertical ? 1080 : 1920, h = vertical ? 1440 : 1080
    let fg = dark ? ivory : ink, accent = dark ? darkGold : gold
    let mark = vertical ? "translate(210 200) scale(5.15625)" : "translate(1060 148) scale(6.125)"
    let name = textPath("光集", size: vertical ? 88 : 94, x: vertical ? 96 : 128, baseline: vertical ? 1040 : 460, semibold: true)
    let line = textPath("把光，收进画面。", size: vertical ? 36 : 38, x: vertical ? 96 : 130, baseline: vertical ? 1130 : 554)
    let sub = textPath("调色 · 片段 · Live", size: 25, x: vertical ? 100 : 132, baseline: vertical ? 1225 : 643)
    let content = "<rect width=\"\(w)\" height=\"\(h)\" fill=\"#\(dark ? "000000" : "FFFFFF")\"/><g transform=\"\(mark)\">\(markSVG(fg, accent))</g><path d=\"\(pathSVG(name))\" fill=\"#\(fg)\"/><path d=\"\(pathSVG(line))\" fill=\"#\(fg)\"/><path d=\"\(pathSVG(sub))\" fill=\"#\(accent)\"/><rect x=\"\(vertical ? 100 : 132)\" y=\"\(vertical ? 1280 : 716)\" width=\"56\" height=\"3\" fill=\"#\(accent)\"/>"
    try svg(vertical ? "key-visuals/guangji-poster" : "key-visuals/guangji-hero-" + (dark ? "dark" : "light"), width: w, height: h, content: content)
}
try heroSVG(dark: false); try heroSVG(dark: true); try heroSVG(dark: true, vertical: true)
for dark in [false, true] {
    try bitmap("key-visuals/guangji-hero-" + (dark ? "dark" : "light"), width: 1920, height: 1080) { paintHero($0, dark: dark) }
}
try bitmap("key-visuals/guangji-poster", width: 1080, height: 1440) { paintHero($0, dark: true, vertical: true) }
// Tiny preview strip checks the real icon at Finder/Dock sizes.
try bitmap("icons/size-review", width: 1024, height: 260) { ctx in
    ctx.setFillColor(color("FFFFFF")); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 260))
    for (i, size) in [16, 32, 64, 128].enumerated() {
        ctx.saveGState(); ctx.translateBy(x: 100 + CGFloat(i) * 220, y: 30 + CGFloat(128 - size) / 2); paintIcon(ctx, size: size); ctx.restoreGState()
        drawText(ctx, "\(size) px", size: 17, x: 90 + CGFloat(i) * 220, baseline: 200, fill: ink)
    }
}
print("Brand vectors, PNG exports, outlined wordmarks, iconset and key visuals exported.")

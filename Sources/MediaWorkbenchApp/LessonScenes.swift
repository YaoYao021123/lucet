import CoreImage
import MediaCore
import SwiftUI

// MARK: - Pixels → brightness → histogram

/// One animation in three acts: the photo breaks into blocks, the blocks lose their colour,
/// then fly into columns by brightness and pile up into a histogram.
struct PixelScene: View {
    let scene: LessonScene
    let photo: LessonPhoto
    let started: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(started)
            Canvas { context, size in draw(&context, size, t) }
        }
    }

    private func ease(_ t: Double) -> Double { let x = min(1, max(0, t)); return x * x * (3 - 2 * x) }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let histogramArea = scene == .histogramBuild
        let photoBox = CGRect(x: 0, y: 0, width: size.width, height: histogramArea ? size.height * 0.5 : size.height - 40)
        let aspect = Double(photo.width) / Double(photo.height)
        let fit = min(photoBox.width / aspect, photoBox.height)
        let rect = CGRect(x: photoBox.midX - fit * aspect / 2, y: photoBox.minY + (photoBox.height - fit) / 2, width: fit * aspect, height: fit)
        let cellW = rect.width / Double(photo.gridWidth), cellH = rect.height / Double(photo.gridHeight)

        switch scene {
        case .pixelGrid:
            let grid = ease(t / 0.8), mosaic = ease((t - 0.9) / 0.9)
            context.draw(Image(decorative: photo.thumbnail, scale: 1), in: rect)
            for block in photo.blocks {
                let cell = CGRect(x: rect.minX + Double(block.x) * cellW, y: rect.minY + Double(block.y) * cellH, width: cellW, height: cellH)
                context.fill(Path(cell), with: .color(Color(red: block.r, green: block.g, blue: block.b).opacity(mosaic)))
                context.stroke(Path(cell), with: .color(.white.opacity(0.25 * grid)), lineWidth: 0.5)
            }
            caption(&context, size, mosaic > 0.5 ? "每一格只有一种颜色：这就是像素（这里放大了很多倍）。" : "")
        case .brightnessOnly:
            let grey = ease(t / 1.2)
            for (i, block) in photo.blocks.enumerated() {
                let cell = CGRect(x: rect.minX + Double(block.x) * cellW, y: rect.minY + Double(block.y) * cellH, width: cellW, height: cellH)
                let r = block.r + (block.luma - block.r) * grey, g = block.g + (block.luma - block.g) * grey, b = block.b + (block.luma - block.b) * grey
                context.fill(Path(cell), with: .color(Color(red: r, green: g, blue: b)))
                context.stroke(Path(cell), with: .color(.white.opacity(0.18)), lineWidth: 0.5)
                if grey > 0.95, i % 23 == 7, cellW > 14 {
                    context.draw(Text("\(Int(block.luma * 100))").font(.system(size: min(10, cellW * 0.45), weight: .semibold))
                        .foregroundStyle(block.luma > 0.55 ? Color.black : Color.white), at: CGPoint(x: cell.midX, y: cell.midY))
                }
            }
            // A brightness scale under the picture.
            let bar = CGRect(x: rect.minX, y: rect.maxY + 14, width: rect.width, height: 8)
            context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .linearGradient(Gradient(colors: [.black, .white]),
                startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
            context.draw(Text("0 纯黑").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: bar.minX + 18, y: bar.maxY + 10))
            context.draw(Text("100 纯白").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: bar.maxX - 22, y: bar.maxY + 10))
        default: // histogramBuild
            let bins = 30
            var counts = [Int](repeating: 0, count: bins)
            var slot = [Int](repeating: 0, count: photo.blocks.count)
            for (i, block) in photo.blocks.enumerated() {
                let bin = min(bins - 1, Int(block.luma * Double(bins)))
                slot[i] = counts[bin]; counts[bin] += 1
            }
            let tallest = Double(max(1, counts.max() ?? 1))
            let base = size.height - 34
            let area = CGRect(x: 0, y: size.height * 0.55, width: size.width, height: base - size.height * 0.55)
            let colW = area.width / Double(bins), blockH = min(colW, area.height / tallest)
            for (i, block) in photo.blocks.enumerated() {
                let bin = min(bins - 1, Int(block.luma * Double(bins)))
                let start = CGRect(x: rect.minX + Double(block.x) * cellW, y: rect.minY + Double(block.y) * cellH, width: cellW, height: cellH)
                let end = CGRect(x: area.minX + Double(bin) * colW + colW * 0.06, y: base - Double(slot[i] + 1) * blockH,
                                 width: colW * 0.88, height: blockH * 0.9)
                // Darker blocks leave first, so the pile grows from left to right.
                let p = ease((t - 0.3 - block.luma * 1.1) / 0.9)
                let frame = CGRect(x: start.minX + (end.minX - start.minX) * p, y: start.minY + (end.minY - start.minY) * p,
                                   width: start.width + (end.width - start.width) * p, height: start.height + (end.height - start.height) * p)
                context.fill(Path(frame), with: .color(Color(white: block.luma)))
            }
            // Brightness axis and zones, once the pile has formed.
            let axis = ease((t - 2.4) / 0.6)
            let bar = CGRect(x: area.minX, y: base + 2, width: area.width, height: 4)
            context.fill(Path(bar), with: .linearGradient(Gradient(colors: [.black, .white]), startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
            for zone in ToneZone.allCases {
                let mid = (zone.range.lowerBound + zone.range.upperBound) / 2
                context.draw(Text(zone.title).font(.caption2).foregroundStyle(Color.secondary.opacity(axis)), at: CGPoint(x: area.minX + area.width * mid, y: base + 18))
            }
        }
    }

    private func caption(_ context: inout GraphicsContext, _ size: CGSize, _ text: String) {
        context.draw(Text(text).font(.callout).foregroundStyle(.secondary), at: CGPoint(x: size.width / 2, y: size.height - 14))
    }
}

// MARK: - Reading the histogram and zones

struct HistogramReadScene: View {
    let photo: LessonPhoto
    var body: some View {
        let shares = ToneZone.shares(photo.histogram)
        VStack(spacing: 18) {
            LessonImage(image: photo.thumbnail).frame(maxHeight: 250)
            ZoneHistogram(histogram: photo.histogram, height: 120)
            HStack(spacing: 8) {
                ForEach(ToneZone.allCases, id: \.self) { zone in
                    VStack(spacing: 4) {
                        GeometryReader { proxy in
                            let share = shares[zone] ?? 0
                            VStack { Spacer(); RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.55))
                                .frame(height: max(2, proxy.size.height * min(1, share * 1.6))) }
                        }
                        .frame(height: 50)
                        Text("\(Int(((shares[zone] ?? 0) * 100).rounded()))%").font(.caption.monospacedDigit())
                        Text(zone.title).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ZoneExplorerScene: View {
    let photo: LessonPhoto
    @UIState private var zone: ToneZone? = .midtones
    var body: some View {
        let shares = ToneZone.shares(photo.histogram)
        VStack(spacing: 14) {
            LessonImage(image: zone.map { photo.zoneMask($0) } ?? photo.thumbnail,
                        caption: zone.map { "彩色的地方属于「\($0.title)」，比如\($0.example)。" } ?? "点下面的区域试试。")
                .frame(maxHeight: 330)
                .animation(.easeInOut(duration: 0.2), value: zone)
            ZoneHistogram(histogram: photo.histogram, height: 70, selectedZone: zone)
            HStack(spacing: 6) {
                ForEach(ToneZone.allCases, id: \.self) { item in
                    Button { zone = zone == item ? nil : item } label: {
                        VStack(spacing: 2) {
                            Text(item.title).font(.callout.weight(zone == item ? .semibold : .regular))
                            Text("\(Int(((shares[item] ?? 0) * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(zone == item ? WorkbenchTheme.selection : WorkbenchTheme.well))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct KeyStylesScene: View {
    let photo: LessonPhoto
    @UIState private var renders: [(String, CGImage, [Double])] = []
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(renders.indices, id: \.self) { i in
                VStack(spacing: 8) {
                    LessonImage(image: renders[i].1, caption: renders[i].0)
                    ZoneHistogram(histogram: renders[i].2, height: 44, showsCaption: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            var low = BasicAdjustments(); low.exposure = -1.1; low.contrast = 15
            var high = BasicAdjustments(); high.exposure = 0.9; high.shadows = 30; high.contrast = -10
            renders = [("暗调：大部分在左边", low), ("原图", BasicAdjustments()), ("亮调：大部分在右边", high)].map { name, a in
                let r = photo.render(a)
                return (name, r.image, LessonPhoto.histogram(of: r.pixels))
            }
        }
    }
}

struct ClippingScene: View {
    let photo: LessonPhoto
    @UIState private var exposure = 1.2
    @UIState private var mark = true
    var body: some View {
        var a = BasicAdjustments(); a.exposure = exposure
        let r = photo.render(a)
        let clip = photo.clipping(r.pixels)
        return VStack(spacing: 12) {
            LessonImage(image: mark ? clip.image : r.image,
                        caption: String(format: "纯白 %.1f%% · 纯黑 %.1f%%", clip.white * 100, clip.black * 100))
                .frame(maxHeight: 330)
            ZoneHistogram(histogram: LessonPhoto.histogram(of: r.pixels), height: 70, showsCaption: false)
            LessonSlider(title: "曝光", value: $exposure, range: -3...3, format: { String(format: "%+.1f EV", $0) })
            Toggle("标出纯白（红）和纯黑（蓝）", isOn: $mark).toggleStyle(.checkbox).font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Tone controls

/// Input → output brightness, the language of curves, for any set of basic adjustments.
struct TransferPlot: View {
    var mapping: (Double) -> Double
    var body: some View {
        Canvas { context, size in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 14)
            context.stroke(Path(box), with: .color(.white.opacity(0.15)), lineWidth: 1)
            var diagonal = Path(); diagonal.move(to: CGPoint(x: box.minX, y: box.maxY)); diagonal.addLine(to: CGPoint(x: box.maxX, y: box.minY))
            context.stroke(diagonal, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var line = Path()
            for step in 0...100 {
                let x = Double(step) / 100, y = mapping(x)
                let point = CGPoint(x: box.minX + box.width * x, y: box.maxY - box.height * y)
                if step == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(.white), lineWidth: 2)
            context.draw(Text("原来的亮度 →").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: box.midX, y: size.height - 4))
            context.draw(Text("现在 ↑").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: 14, y: 6))
        }
    }
}

struct ExposureBrightnessScene: View {
    let photo: LessonPhoto
    @UIState private var exposure = 0.0
    @UIState private var brightness = 0.0
    var body: some View {
        var a = BasicAdjustments(); a.exposure = exposure; a.brightness = brightness
        let r = photo.render(a)
        let adjustments = a
        return VStack(spacing: 12) {
            HStack(spacing: 16) {
                LessonImage(image: r.image).frame(maxWidth: .infinity)
                TransferPlot { ToneResponse.map($0, adjustments) }.frame(width: 220, height: 220)
            }
            .frame(maxHeight: 300)
            ZoneHistogram(histogram: LessonPhoto.histogram(of: r.pixels), height: 64, showsCaption: false)
            LessonSlider(title: "曝光", value: $exposure, range: -2...2, format: { String(format: "%+.1f EV", $0) })
            LessonSlider(title: "亮度", value: $brightness, range: -100...100)
            Text(exposure > 0.3 ? "看右上角：曝光让亮的地方先碰到顶（变成纯白）。"
                 : brightness > 20 ? "亮度把整条线往上挪，暗的和亮的差不多一起变化。" : "分别拖动两个滑块，比较右边线的形状。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ToneControlScene: View {
    let photo: LessonPhoto
    private let controls: [AdjustmentParameter] = [.highlights, .shadows, .whites, .blackPoint]
    @UIState private var control = AdjustmentParameter.shadows
    @UIState private var values: [AdjustmentParameter: Double] = [:]
    @UIState private var showArea = true
    var body: some View {
        var a = BasicAdjustments(); a[control] = values[control] ?? 0
        let r = photo.render(a)
        return VStack(spacing: 12) {
            GlassSegmentedControl(options: controls, selection: $control, title: { $0.title }, size: .small)
                .frame(maxWidth: 320)
            LessonImage(image: showArea ? photo.influence(control, on: r.pixels) : r.image,
                        caption: showArea ? "彩色 = 「\(control.title)」会改变的地方" : nil)
                .frame(maxHeight: 290)
            ZoneHistogram(histogram: LessonPhoto.histogram(of: r.pixels), focus: control, height: 64)
            LessonSlider(title: control.title, value: Binding(get: { values[control] ?? 0 }, set: { values[control] = $0 }), range: -100...100)
            Toggle("显示作用范围", isOn: $showArea).toggleStyle(.checkbox).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Curves

struct CurveScene: View {
    let photo: LessonPhoto
    let shapes: Bool
    @UIState private var points: [CurvePoint] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.5), CurvePoint(x: 1, y: 1)]
    @UIState private var shape = 0

    private static let presets: [(String, [CurvePoint])] = [
        ("原样", [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]),
        ("变亮", [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.63), CurvePoint(x: 1, y: 1)]),
        ("变暗", [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.37), CurvePoint(x: 1, y: 1)]),
        ("S 形：对比更强", [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.17), CurvePoint(x: 0.75, y: 0.83), CurvePoint(x: 1, y: 1)]),
        ("反 S：更柔和", [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.33), CurvePoint(x: 0.75, y: 0.67), CurvePoint(x: 1, y: 1)]),
    ]

    var body: some View {
        var curves = ToneCurves(); curves.master = points
        let r = photo.render(MediaEdits(curves: curves))
        return VStack(spacing: 12) {
            HStack(spacing: 16) {
                LessonImage(image: r.image).frame(maxWidth: .infinity)
                editor.frame(width: 250, height: 250)
            }
            .frame(maxHeight: 300)
            ZoneHistogram(histogram: LessonPhoto.histogram(of: r.pixels), height: 60, showsCaption: false)
            if shapes {
                HStack(spacing: 6) {
                    ForEach(Self.presets.indices, id: \.self) { i in
                        Button(Self.presets[i].0) { shape = i; points = Self.presets[i].1 }
                            .buttonStyle(.plain).font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(shape == i ? WorkbenchTheme.selection : WorkbenchTheme.well))
                    }
                }
            } else if points.count == 3 {
                Text("原来 \(Int(points[1].x * 100)) → 现在 \(Int(points[1].y * 100))：比它暗的和比它亮的，都跟着平滑变化。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Axes labelled with the zones; in the first step the middle point can be dragged.
    private var editor: some View {
        GeometryReader { proxy in
            let box = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 22, dy: 16)
            ZStack {
                Canvas { context, _ in
                    for i in 1..<5 {
                        let x = box.minX + box.width * Double(i) / 5, y = box.minY + box.height * Double(i) / 5
                        var grid = Path(); grid.move(to: CGPoint(x: x, y: box.minY)); grid.addLine(to: CGPoint(x: x, y: box.maxY))
                        grid.move(to: CGPoint(x: box.minX, y: y)); grid.addLine(to: CGPoint(x: box.maxX, y: y))
                        context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
                    }
                    context.stroke(Path(box), with: .color(.white.opacity(0.2)), lineWidth: 1)
                    var diagonal = Path(); diagonal.move(to: CGPoint(x: box.minX, y: box.maxY)); diagonal.addLine(to: CGPoint(x: box.maxX, y: box.minY))
                    context.stroke(diagonal, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    let samples = ToneCurves.sample(points, count: 101)
                    var line = Path()
                    for (i, y) in samples.enumerated() {
                        let p = CGPoint(x: box.minX + box.width * Double(i) / 100, y: box.maxY - box.height * y)
                        if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                    }
                    context.stroke(line, with: .color(.white), lineWidth: 2)
                    for point in points.dropFirst().dropLast() {
                        let p = CGPoint(x: box.minX + box.width * point.x, y: box.maxY - box.height * point.y)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                    }
                    context.draw(Text("原来 → 暗 … 亮").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: box.midX, y: box.maxY + 9))
                    context.draw(Text("现在").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: box.minX - 11, y: box.minY + 6))
                }
                if !shapes {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let x = min(0.9, max(0.1, (value.location.x - box.minX) / box.width))
                            let y = min(0.98, max(0.02, (box.maxY - value.location.y) / box.height))
                            points = [CurvePoint(x: 0, y: 0), CurvePoint(x: x, y: y), CurvePoint(x: 1, y: 1)]
                        })
                }
            }
        }
    }
}

// MARK: - Camera: aperture, depth of field, shutter, ISO

private let fStops: [Double] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]
private let shutterStops: [Double] = [1.0 / 1000, 1.0 / 500, 1.0 / 250, 1.0 / 125, 1.0 / 60, 1.0 / 30, 1.0 / 15, 1.0 / 8, 1.0 / 4]
private let isoStops: [Int] = [100, 200, 400, 800, 1600, 3200, 6400, 12800]
private func shutterLabel(_ t: Double) -> String { t >= 1 ? String(format: "%.0f 秒", t) : "1/\(Int((1 / t).rounded())) 秒" }
private func stopLabel(_ f: Double) -> String { f < 10 ? String(format: "ƒ/%.1f", f).replacingOccurrences(of: ".0", with: "") : String(format: "ƒ/%.0f", f) }

struct ApertureScene: View {
    let photo: LessonPhoto
    @UIState private var stop = 2.0
    var body: some View {
        let f = fStops[Int(stop.rounded())]
        let focal = photo.capture?.focalLengthMM ?? 50
        let diameter = focal / f
        let lessLight = pow(2, log2(f / 1.4) * 2)
        return VStack(spacing: 14) {
            Canvas { context, size in
                // Front view: the opening.
                let front = CGPoint(x: size.width * 0.25, y: size.height / 2)
                let barrel = min(size.height * 0.42, size.width * 0.2)
                let ring = Path(ellipseIn: CGRect(x: front.x - barrel, y: front.y - barrel, width: barrel * 2, height: barrel * 2))
                context.fill(ring, with: .color(Color(white: 0.2)))
                context.stroke(ring, with: .color(.white.opacity(0.45)), lineWidth: 1.5)
                let opening = barrel * 0.92 * 1.4 / f
                var blades = Path()
                for i in 0...9 {
                    let angle = Double(i) / 9 * 2 * .pi
                    let p = CGPoint(x: front.x + cos(angle) * opening, y: front.y + sin(angle) * opening)
                    if i == 0 { blades.move(to: p) } else { blades.addLine(to: p) }
                }
                context.fill(blades, with: .color(Color(white: 0.85)))
                context.draw(Text("正面看：开口").font(.caption).foregroundStyle(.secondary), at: CGPoint(x: front.x, y: front.y + barrel + 14))
                // Side view: a cone of light through the opening onto the sensor.
                let lensX = size.width * 0.62, sensorX = size.width * 0.9, mid = size.height / 2
                let source = CGPoint(x: size.width * 0.45, y: mid)
                var cone = Path()
                cone.move(to: source); cone.addLine(to: CGPoint(x: lensX, y: mid - opening)); cone.addLine(to: CGPoint(x: sensorX, y: mid))
                cone.addLine(to: CGPoint(x: lensX, y: mid + opening)); cone.closeSubpath()
                context.fill(cone, with: .color(Color(red: 1, green: 0.9, blue: 0.6).opacity(0.18 + 0.5 * 1.4 / f)))
                var lens = Path(); lens.move(to: CGPoint(x: lensX, y: mid - barrel)); lens.addLine(to: CGPoint(x: lensX, y: mid - opening))
                lens.move(to: CGPoint(x: lensX, y: mid + opening)); lens.addLine(to: CGPoint(x: lensX, y: mid + barrel))
                context.stroke(lens, with: .color(.white), lineWidth: 3)
                context.fill(Path(CGRect(x: sensorX, y: mid - barrel * 0.5, width: 4, height: barrel)), with: .color(.white.opacity(0.7)))
                context.draw(Text("侧面看：进来的光").font(.caption).foregroundStyle(.secondary), at: CGPoint(x: (lensX + sensorX) / 2, y: mid + barrel + 14))
            }
            .frame(maxHeight: 300)
            Text(String(format: "开口直径 = %.0f mm ÷ %.1f ≈ %.1f mm", focal, f, diameter)).font(.title3.monospacedDigit())
            Text(f == 1.4 ? "最大的开口，进光最多。" : String(format: "进来的光只有 ƒ/1.4 的 1/%.0f。", lessLight))
                .font(.callout).foregroundStyle(.secondary)
            LessonSlider(title: "光圈", value: $stop, range: 0...Double(fStops.count - 1), format: { stopLabel(fStops[Int($0.rounded())]) })
            if let capture = photo.capture, let fn = capture.fNumber {
                Text("你这张照片用的是 \(stopLabel(fn))" + (capture.focalLengthMM.map { String(format: "，焦距 %.1f mm，开口约 %.1f mm。", $0, $0 / fn) } ?? "。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DepthOfFieldScene: View {
    @UIState private var stop = 1.0
    var body: some View {
        let f = fStops[Int(stop.rounded())]
        // Relative sharp range: grows with the f-number (simplified, same distance and lens).
        let depth = 0.06 + 0.5 * (f - 1.4) / (16 - 1.4)
        let blur = max(0, 14 * (1.4 / f) - 0.8)
        return VStack(spacing: 14) {
            HStack(spacing: 16) {
                Canvas { context, size in
                    // The scene from the side: camera, sharp band, three objects.
                    let ground = size.height * 0.75
                    let camera = CGPoint(x: 24, y: ground - 16)
                    context.fill(Path(roundedRect: CGRect(x: camera.x - 14, y: camera.y - 10, width: 28, height: 20), cornerRadius: 4), with: .color(.white.opacity(0.8)))
                    let subjectX = size.width * 0.5
                    let band = CGRect(x: subjectX - size.width * depth / 2, y: 12, width: size.width * depth, height: ground - 12)
                    context.fill(Path(band), with: .color(.white.opacity(0.12)))
                    context.draw(Text("清楚的范围").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: subjectX, y: 8))
                    let objects: [(Double, String)] = [(0.28, "🌼"), (0.5, "🧍"), (0.82, "🌲")]
                    for (x, emoji) in objects {
                        let inside = band.minX...band.maxX ~= size.width * x
                        var layer = context
                        if !inside { layer.addFilter(.blur(radius: min(6, blur * 0.4))) }
                        layer.draw(Text(emoji).font(.system(size: 30)), at: CGPoint(x: size.width * x, y: ground - 20))
                    }
                    var line = Path(); line.move(to: CGPoint(x: 0, y: ground)); line.addLine(to: CGPoint(x: size.width, y: ground))
                    context.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 1)
                }
                .frame(maxWidth: .infinity)
                Canvas { context, size in
                    // What the photo looks like: background lights soften as the opening grows.
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.1, green: 0.13, blue: 0.2), Color(red: 0.05, green: 0.06, blue: 0.08)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: blur))
                        for i in 0..<14 {
                            let x = size.width * Double((i * 37) % 100) / 100, y = size.height * (0.15 + Double((i * 53) % 40) / 100)
                            let r = 5.0 + Double(i % 3) * 3
                            layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                       with: .color([Color.orange, .yellow, .white, .pink][i % 4].opacity(0.85)))
                        }
                        layer.fill(Path(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38)), with: .color(Color(red: 0.1, green: 0.16, blue: 0.1)))
                    }
                    // The subject stays sharp.
                    let cx = size.width * 0.5, top = size.height * 0.32
                    context.fill(Path(ellipseIn: CGRect(x: cx - 18, y: top, width: 36, height: 40)), with: .color(Color(red: 0.86, green: 0.72, blue: 0.62)))
                    context.fill(Path(roundedRect: CGRect(x: cx - 40, y: top + 44, width: 80, height: size.height - top - 44), cornerRadius: 18), with: .color(Color(red: 0.2, green: 0.3, blue: 0.5)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 320)
            LessonSlider(title: "光圈", value: $stop, range: 0...Double(fStops.count - 1), format: { stopLabel(fStops[Int($0.rounded())]) })
            Text(f <= 2.8 ? "开口大：只有人是清楚的，背景的灯变成柔和的光斑。" : f >= 8 ? "开口小：从近处的花到远处的树都清楚，适合风景。" : "中间档：主体清楚，背景略有虚化。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct ShutterScene: View {
    let photo: LessonPhoto
    @UIState private var stop = 3.0
    var body: some View {
        let time = shutterStops[Int(stop.rounded())]
        let stopsBrighter = log2(time / (1.0 / 125))
        var a = BasicAdjustments(); a.exposure = min(3, max(-3, stopsBrighter))
        let background = photo.render(a).image
        return VStack(spacing: 14) {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.draw(Image(decorative: background, scale: 1), in: rect)
                    // A ball crossing the frame at 600 points per second: the streak is what the
                    // sensor sees while the shutter is open.
                    let speed = 600.0
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
                    let x = -40 + (size.width + 80) * phase, y = size.height * 0.55
                    let streak = max(0, speed * time)
                    let steps = max(1, Int(min(60, streak / 3)))
                    for i in 0...steps {
                        let px = x - streak * Double(i) / Double(steps)
                        context.fill(Path(ellipseIn: CGRect(x: px - 16, y: y - 16, width: 32, height: 32)),
                                     with: .color(Color.orange.opacity(min(1, 1.6 / Double(steps + 1)))))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxHeight: 320)
            LessonSlider(title: "快门", value: $stop, range: 0...Double(shutterStops.count - 1), format: { shutterLabel(shutterStops[Int($0.rounded())]) })
            Text(time <= 1.0 / 500 ? "快门很快：运动被冻结，但画面变暗了。" : time >= 1.0 / 30 ? "快门慢：画面变亮，但运动的东西拖出了影子。" : "中间档：亮度合适，运动略有拖影。")
                .font(.callout).foregroundStyle(.secondary)
            if let focal = photo.capture?.focalLength35mm, let shot = photo.capture?.exposureTime {
                Text("你这张照片用了 \(shutterLabel(shot))；按等效焦距 \(Int(focal)) mm，手持时最好快于 1/\(Int(focal)) 秒。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The photo at this exposure with sensor-like grain for the ISO: grey, stronger in the shadows,
/// and the same pattern every time (seeded), so dragging doesn't flicker.
private func noisy(_ photo: LessonPhoto, iso: Int, exposure: Double) -> CGImage {
    var a = BasicAdjustments(); a.exposure = exposure
    var pixels = photo.render(a).pixels
    let strength = 70 * pow(Double(iso) / 12800, 0.8)   // ± levels out of 255 at ISO 12800
    guard iso > 100, !pixels.isEmpty else { return LessonPhoto.cgImage(pixels, photo.width, photo.height) ?? photo.thumbnail }
    var seed: UInt64 = 0x9E3779B97F4A7C15
    for i in 0..<(pixels.count / 4) {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let u1 = Double((seed >> 11) & 0xFFFFF) / Double(0xFFFFF), u2 = Double((seed >> 33) & 0xFFFFF) / Double(0xFFFFF)
        let gaussian = (u1 + u2 - 1) * 1.7
        let luma = (0.2126 * Double(pixels[i * 4]) + 0.7152 * Double(pixels[i * 4 + 1]) + 0.0722 * Double(pixels[i * 4 + 2])) / 255
        let delta = gaussian * strength * (1.2 - 0.6 * luma)
        for c in 0..<3 { pixels[i * 4 + c] = UInt8(min(255, max(0, Double(pixels[i * 4 + c]) + delta))) }
    }
    return LessonPhoto.cgImage(pixels, photo.width, photo.height) ?? photo.thumbnail
}

struct ISOScene: View {
    let photo: LessonPhoto
    @UIState private var stop = 3.0
    var body: some View {
        let iso = isoStops[Int(stop.rounded())]
        // A dim room: at ISO 100 it is 3 stops too dark; each ISO step makes up one stop.
        let image = noisy(photo, iso: iso, exposure: log2(Double(iso) / 800))
        return VStack(spacing: 14) {
            LessonImage(image: image, caption: "同样的弱光，只改变 ISO").frame(maxHeight: 340)
            LessonSlider(title: "ISO", value: $stop, range: 0...Double(isoStops.count - 1), format: { "\(isoStops[Int($0.rounded())])" })
            Text(iso <= 200 ? "ISO 低：干净，但光不够时太暗。" : iso >= 3200 ? "ISO 高：亮了，但颗粒（噪点）也明显了。" : "中间档：亮度和噪点的折中。")
                .font(.callout).foregroundStyle(.secondary)
            if let shot = photo.capture?.isoValue {
                Text("你这张照片用的是 ISO \(shot)。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ExposureTriangleScene: View {
    let photo: LessonPhoto
    @UIState private var aperture = 2.0   // ƒ/2.8
    @UIState private var shutter = 3.0    // 1/125
    @UIState private var iso = 2.0        // 400
    var body: some View {
        let a = Int(aperture.rounded()), s = Int(shutter.rounded()), i = Int(iso.rounded())
        // Each f-stop step lets in half the light; each shutter and ISO step doubles it.
        let ev = Double(2 - a) + Double(s - 3) + Double(i - 2)
        let image = noisy(photo, iso: isoStops[i], exposure: min(3, max(-3, ev)))
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                LessonImage(image: image).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    meter(ev)
                    effect("背景虚化", 1 - Double(a) / 7, a <= 2 ? "背景虚" : a >= 5 ? "前后都清楚" : "略虚")
                    effect("拖影风险", Double(s) / 8, s >= 5 ? "容易糊" : s <= 2 ? "冻结运动" : "一般")
                    effect("噪点", Double(i) / 7, i >= 5 ? "明显" : i <= 1 ? "干净" : "轻微")
                }
                .frame(width: 200)
            }
            .frame(maxHeight: 300)
            LessonSlider(title: "光圈", value: $aperture, range: 0...7, format: { stopLabel(fStops[Int($0.rounded())]) })
            LessonSlider(title: "快门", value: $shutter, range: 0...8, format: { shutterLabel(shutterStops[Int($0.rounded())]) })
            LessonSlider(title: "ISO", value: $iso, range: 0...7, format: { "\(isoStops[Int($0.rounded())])" })
        }
    }

    private func meter(_ ev: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(abs(ev) < 0.5 ? "亮度正好" : ev > 0 ? String(format: "亮了 %.0f 档", ev) : String(format: "暗了 %.0f 档", -ev))
                .font(.callout.weight(.semibold))
            GeometryReader { proxy in
                let x = proxy.size.width * (min(3, max(-3, ev)) + 3) / 6
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [.black, .gray, .white], startPoint: .leading, endPoint: .trailing)).frame(height: 6)
                    Rectangle().fill(Color.white.opacity(0.6)).frame(width: 1, height: 14).offset(x: proxy.size.width / 2)
                    Circle().fill(Color.white).frame(width: 12, height: 12).offset(x: x - 6)
                }
            }
            .frame(height: 14)
        }
    }

    private func effect(_ title: String, _ amount: Double, _ word: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title).font(.caption); Spacer(); Text(word).font(.caption).foregroundStyle(.secondary) }
            GeometryReader { proxy in
                Capsule().fill(WorkbenchTheme.well).overlay(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.7)).frame(width: max(4, proxy.size.width * min(1, max(0, amount))))
                }
            }
            .frame(height: 5)
        }
    }
}

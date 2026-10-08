import MediaCore
import SwiftUI

/// Brightness histogram split into the five named zones. When a tone control is hovered or
/// dragged, the part of the histogram it moves is shaded (from the app's real formulas) and its
/// zones light up — so every slider shows what it touches.
struct ZoneHistogram: View {
    let histogram: [Double]
    var focus: AdjustmentParameter?
    var height: CGFloat = 56

    var body: some View {
        VStack(spacing: 3) {
            Canvas { context, size in draw(&context, size) }
                .frame(height: height)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            labels
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: focus)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("亮度分布：" + caption)
    }

    private var active: Set<ToneZone> {
        guard let focus else { return [] }
        return Set(ToneZone.allCases.filter { ToneResponse.weight(focus, at: ($0.range.lowerBound + $0.range.upperBound) / 2) > 0.35 })
    }

    private var caption: String {
        guard let focus else {
            let shares = ToneZone.shares(histogram)
            guard let main = shares.max(by: { $0.value < $1.value }) else { return "左暗右亮；山峰在哪里，照片的大部分就在哪里。" }
            return "左暗右亮。这张照片的大部分在「\(main.key.title)」（\(Int((main.value * 100).rounded()))%）。"
        }
        let zones = ToneZone.allCases.filter { active.contains($0) }.map(\.title)
        if focus == .brightness { return "亮度：整体一起移动，所有区域同等变化。" }
        if focus == .contrast { return "对比度：两端向外拉开（或收拢），中间调基本不动。" }
        return "\(title(focus))：主要改变「\(zones.joined(separator: "」「"))」，阴影部分是它作用的范围。"
    }

    private func title(_ p: AdjustmentParameter) -> String {
        SimpleControl.all.first { $0.parameter == p }.map { "\($0.title)（\(p.title)）" } ?? p.title
    }

    private var labels: some View {
        GeometryReader { proxy in
            ForEach(ToneZone.allCases, id: \.self) { zone in
                let mid = (zone.range.lowerBound + zone.range.upperBound) / 2
                Text(zone.title)
                    .font(.system(size: 9, weight: active.contains(zone) ? .semibold : .regular))
                    .foregroundStyle(active.contains(zone) ? Color.primary : Color.secondary.opacity(0.8))
                    .fixedSize()
                    .position(x: proxy.size.width * mid, y: 6)
                    .help("\(zone.title)：\(zone.example)")
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.15), value: focus)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        // Zone backgrounds: a dark-to-light strip so position reads as brightness.
        for zone in ToneZone.allCases {
            let rect = CGRect(x: size.width * zone.range.lowerBound, y: size.height - 3,
                              width: size.width * (zone.range.upperBound - zone.range.lowerBound), height: 3)
            let mid = (zone.range.lowerBound + zone.range.upperBound) / 2
            context.fill(Path(rect), with: .color(Color(white: mid)))
            if zone != .deepShadows {
                var line = Path(); line.move(to: CGPoint(x: rect.minX, y: 0)); line.addLine(to: CGPoint(x: rect.minX, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            }
        }
        // Where the focused control acts.
        if let focus {
            var area = Path(); area.move(to: CGPoint(x: 0, y: size.height))
            for step in 0...100 {
                let y = Double(step) / 100
                area.addLine(to: CGPoint(x: size.width * y, y: size.height * (1 - ToneResponse.weight(focus, at: y) * 0.92)))
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
            context.fill(area, with: .color(.white.opacity(0.13)))
        }
        // The histogram itself.
        guard histogram.count > 1 else { return }
        var shape = Path(); shape.move(to: CGPoint(x: 0, y: size.height - 3))
        for (index, value) in histogram.enumerated() {
            let x = size.width * Double(index) / Double(histogram.count - 1)
            shape.addLine(to: CGPoint(x: x, y: (size.height - 3) * (1 - sqrt(value) * 0.92)))
        }
        shape.addLine(to: CGPoint(x: size.width, y: size.height - 3)); shape.closeSubpath()
        context.fill(shape, with: .color(.white.opacity(0.32)))
        context.stroke(shape, with: .color(.white.opacity(0.7)), lineWidth: 0.7)
    }
}

/// The zone shading alone, laid over the RGB histogram in 完整 mode.
struct ZoneShading: View {
    var focus: AdjustmentParameter?
    var body: some View {
        Canvas { context, size in
            guard let focus else { return }
            var area = Path(); area.move(to: CGPoint(x: 0, y: size.height))
            for step in 0...100 {
                let y = Double(step) / 100
                area.addLine(to: CGPoint(x: size.width * y, y: size.height * (1 - ToneResponse.weight(focus, at: y) * 0.92)))
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
            context.fill(area, with: .color(.white.opacity(0.13)))
        }
        .allowsHitTesting(false)
    }
}

/// Zone names under the 完整-mode histogram (inset to match its 4 pt padding).
struct ZoneLabels: View {
    var focus: AdjustmentParameter?
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 8
            ForEach(ToneZone.allCases, id: \.self) { zone in
                let mid = (zone.range.lowerBound + zone.range.upperBound) / 2
                let on = focus.map { ToneResponse.weight($0, at: mid) > 0.35 } ?? false
                Text(zone.title)
                    .font(.system(size: 9, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.primary : Color.secondary.opacity(0.8))
                    .fixedSize()
                    .position(x: 4 + width * mid, y: 6)
                    .help("\(zone.title)：\(zone.example)")
            }
        }
        .frame(height: 12)
    }
}

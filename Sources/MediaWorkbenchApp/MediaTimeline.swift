import SwiftUI
import MediaCore

/// Source-time ruler: trim, playhead, and Live cover all share the same coordinate space.
struct MediaTimeline: View {
    var model: WorkbenchModel
    @UIState private var draftStart: Double?
    @UIState private var draftEnd: Double?
    @UIState private var zoomSelection = false
    @UIState private var rangeOrigin: ClipSettings?
    @UIState private var draftCover: Double?
    private var start: Double { draftStart ?? model.clipStart }
    private var end: Double { draftEnd ?? model.clipEnd }
    private var cover: Double { draftCover ?? model.cover }
    private var span: ClosedRange<Double> {
        guard zoomSelection else { return 0...max(0.1, model.duration) }
        let padding = max(0.1, (model.clipEnd - model.clipStart) * 0.25)
        return max(0, model.clipStart - padding)...min(model.duration, model.clipEnd + padding)
    }
    var body: some View {
        VStack(spacing: 0) {
            WorkbenchTheme.hairline.frame(height: 1)
            transport.padding(.horizontal, 14).padding(.vertical, 8)
            timeline.padding(.horizontal, 24).frame(height: 94)
            if let music = model.musicURL {
                HStack(spacing: 8) {
                    Image(systemName: "music.note").foregroundStyle(WorkbenchTheme.accent)
                    Text(music.lastPathComponent).lineLimit(1)
                    Spacer()
                    Text("BGM · \(Int(model.musicVolume * 100))%").foregroundStyle(.secondary)
                }.font(.system(size: 10)).padding(.horizontal, 10).frame(height: 24)
                    .background(WorkbenchTheme.accent.opacity(0.08)).padding(.horizontal, 24).padding(.bottom, 6)
            }
            HStack(spacing: 14) {
                Text("入 \(timeLabel(start))   出 \(timeLabel(end))")
                Spacer(minLength: 0)
                Text("封面 \(timeLabel(cover))").foregroundStyle(WorkbenchTheme.accent)
                Text(String(format: "原片 %.2f s → 输出 %.2f s · %.2f×", end - start, (end - start) / model.playbackSpeed, model.playbackSpeed))
            }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.bottom, 10)
        }.background(WorkbenchTheme.timeline)
    }
    private var transport: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                playbackControls.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                clipControls.fixedSize(horizontal: true, vertical: false)
            }
            VStack(spacing: 8) {
                HStack { playbackControls; Spacer(minLength: 0) }
                HStack { Spacer(minLength: 0); clipControls }
            }
        }.disabled(model.busy)
    }
    private var playbackControls: some View {
        HStack(spacing: 5) {
            IconButton(title: "上一帧", icon: "backward.end") { model.stepFrame(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            IconButton(title: "播放 / 暂停", icon: model.playing ? "pause.fill" : "play.fill", action: model.togglePlayback)
                .keyboardShortcut(.space, modifiers: [])
            IconButton(title: "下一帧", icon: "forward.end") { model.stepFrame(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Text(timeLabel(model.clipStart + model.position)).font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.leading, 8).accessibilityLabel("源素材播放时间").accessibilityValue(timeLabel(model.clipStart + model.position))
            IconButton(title: zoomSelection ? "显示完整素材" : "放大片段", icon: "arrow.left.and.right", active: zoomSelection) { zoomSelection.toggle() }
            IconButton(title: "静音原声", icon: model.originalVolume == 0 ? "speaker.slash" : "speaker.wave.2", active: model.originalVolume == 0) { model.originalVolume = model.originalVolume == 0 ? 1 : 0 }
        }
    }
    private var clipControls: some View {
        HStack(spacing: 8) {
            Button("设为封面", action: model.setCover).workstationButton()
            Button("选取 3 秒 Live", action: model.liveRange).workstationButton()
            liveButton
        }
    }
    private var liveButton: some View {
        let valid = model.clip.outputDuration >= 0.5 && model.clip.outputDuration <= 3.001
        return Button(action: model.exportLive) {
            Label { Text("制作 Live") } icon: { Image(systemName: "livephoto").font(.system(size: 16)) }
        }.workstationPrimaryButton().disabled(!valid)
            .help(valid ? "生成 Live Photo 副本" : "Live 输出需为 0.5–3 秒，可调整范围或速度")
    }
    private var timeline: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let lower = span.lowerBound, seconds = max(0.1, span.upperBound - span.lowerBound)
            let left = x(start, width: width, lower: lower, span: seconds)
            let right = x(end, width: width, lower: lower, span: seconds)
            ZStack(alignment: .topLeading) {
                TimelineRuler(lower: lower, duration: seconds).frame(height: 24).allowsHitTesting(false)
                filmstrip.frame(width: width, height: 48).offset(y: 28)
                Rectangle().fill(Color.black.opacity(0.65)).frame(width: left, height: 48).offset(y: 28).allowsHitTesting(false)
                Rectangle().fill(Color.black.opacity(0.65)).frame(width: max(0, width - right), height: 48).offset(x: right, y: 28).allowsHitTesting(false)
                Rectangle().strokeBorder(WorkbenchTheme.accent.opacity(0.9), lineWidth: 1.5)
                    .frame(width: max(1, right - left), height: 48).offset(x: left, y: 28).allowsHitTesting(false)
                Rectangle().fill(.clear).frame(width: width, height: 76).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("sourceTimeline"))
                        .onChanged { event in
                            model.player?.pause(); model.playing = false
                            let source = lower + min(1, max(0, event.location.x / width)) * seconds
                            model.scrubSeek(source - model.clipStart)
                        }
                        .onEnded { event in
                            let source = lower + min(1, max(0, event.location.x / width)) * seconds
                            model.scrubSeek(source - model.clipStart, exact: true)
                        })
                    .accessibilityElement(children: .ignore).accessibilityLabel("播放位置")
                    .accessibilityValue(timeLabel(model.clipStart + model.position))
                    .accessibilityAdjustableAction { direction in model.stepFrame(direction == .increment ? 1 : -1) }
                playhead(at: x(model.clipStart + model.position, width: width, lower: lower, span: seconds))
                Rectangle().fill(.clear).frame(width: max(1, right - left - 12), height: 48)
                    .contentShape(Rectangle()).offset(x: left + 6, y: 28)
                    .gesture(selectionGesture(width: width, lower: lower, seconds: seconds))
                    .help("拖动整体移动选取片段，保持长度；点按定位播放头")
                    .accessibilityLabel("移动选取片段")
                    .accessibilityValue("\(timeLabel(start)) 至 \(timeLabel(end))")
                    .accessibilityAdjustableAction { direction in model.moveRange(by: direction == .increment ? 1 : -1) }
                trimHandle(isStart: true).position(x: left, y: 52)
                    .gesture(trimGesture(isStart: true, width: width, lower: lower, seconds: seconds))
                    .accessibilityLabel("片段起点").accessibilityValue(timeLabel(start))
                    .accessibilityAdjustableAction { direction in
                        let next = start + (direction == .increment ? 1 : -1) / max(1, Double(model.metadata?.nominalFrameRate ?? 30))
                        model.setRange(start: next, end: end)
                    }
                trimHandle(isStart: false).position(x: right, y: 52)
                    .gesture(trimGesture(isStart: false, width: width, lower: lower, seconds: seconds))
                    .accessibilityLabel("片段终点").accessibilityValue(timeLabel(end))
                    .accessibilityAdjustableAction { direction in
                        let next = end + (direction == .increment ? 1 : -1) / max(1, Double(model.metadata?.nominalFrameRate ?? 30))
                        model.setRange(start: start, end: next)
                    }
                Image(systemName: "diamond.fill").font(.system(size: 10)).foregroundStyle(WorkbenchTheme.accent)
                    .frame(width: 24, height: 18).contentShape(Rectangle())
                    .position(x: x(cover, width: width, lower: lower, span: seconds), y: 86)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("sourceTimeline"))
                        .onChanged { event in model.moveCover(to: lower + min(1, max(0, event.location.x / width)) * seconds, exact: false) }
                        .onEnded { event in model.moveCover(to: lower + min(1, max(0, event.location.x / width)) * seconds) })
                    .accessibilityLabel("Live 封面位置").accessibilityValue(timeLabel(cover))
                    .accessibilityAdjustableAction { direction in
                        model.moveCover(to: model.cover + (direction == .increment ? 1 : -1) / max(1, Double(model.metadata?.nominalFrameRate ?? 30)))
                    }.help("拖动选择 Live 封面")
            }.coordinateSpace(name: "sourceTimeline").disabled(model.busy)
        }
    }
    private var filmstrip: some View {
        GeometryReader { geometry in
            // SwiftUI can evaluate an old ForEach child after a new source clears
            // the model array. Capture the frames and layout in the same snapshot.
            let frames = model.thumbnails
            let visibleSpan = span
            let duration = model.duration
            if !frames.isEmpty {
                HStack(spacing: 0) {
                    ForEach(frames.indices, id: \.self) { index in
                        // Reuse the closest cached source frame when the ruler is zoomed.
                        let sourceTime = visibleSpan.lowerBound + (visibleSpan.upperBound - visibleSpan.lowerBound) * Double(index) / Double(max(1, frames.count - 1))
                        let sourceIndex = min(frames.count - 1, max(0, Int((sourceTime / max(0.1, duration) * Double(frames.count - 1)).rounded())))
                        Image(decorative: frames[sourceIndex], scale: 1).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width / Double(frames.count), height: 48).clipped()
                    }
                }.accessibilityHidden(true)
            } else {
                HStack {
                    if model.thumbnailsLoading { ProgressView().controlSize(.mini) }
                    Text(model.thumbnailsLoading ? "正在生成缩略图…" : model.thumbnailNotice ?? "视频片段")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.025))
            }
        }
    }
    private func trimHandle(isStart: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(WorkbenchTheme.accent).frame(width: 8, height: 48)
            Capsule().fill(Color.black.opacity(0.7)).frame(width: 1.5, height: 16)
        }.frame(width: 20, height: 54).contentShape(Rectangle()).help(isStart ? "拖动调整入点" : "拖动调整出点")
    }
    private func selectionGesture(width: CGFloat, lower: Double, seconds: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("sourceTimeline"))
            .onChanged { event in
                guard abs(event.translation.width) >= 2 || rangeOrigin != nil else { return }
                if rangeOrigin == nil { rangeOrigin = model.clip }
                guard let origin = rangeOrigin else { return }
                let rate = max(1, Double(model.metadata?.nominalFrameRate ?? 30))
                let delta = (event.translation.width / width * seconds * rate).rounded() / rate
                let next = origin.shifted(by: delta, duration: model.duration)
                draftStart = next.start; draftEnd = next.end; draftCover = next.cover
            }
            .onEnded { event in
                if let origin = rangeOrigin { model.moveRange(by: start - origin.start) }
                else {
                    let source = lower + min(1, max(0, event.location.x / width)) * seconds
                    model.seek(source - model.clipStart)
                }
                draftStart = nil; draftEnd = nil; draftCover = nil; rangeOrigin = nil
            }
    }
    private func trimGesture(isStart: Bool, width: CGFloat, lower: Double, seconds: Double) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("sourceTimeline"))
            .onChanged { event in
                let rate = max(1, Double(model.metadata?.nominalFrameRate ?? 30))
                let time = ((lower + min(1, max(0, event.location.x / width)) * seconds) * rate).rounded() / rate
                if isStart { draftStart = min(max(0, time), end - 0.1) }
                else { draftEnd = max(start + 0.1, min(model.duration, time)) }
            }
            .onEnded { _ in
                model.setRange(start: start, end: end)
                draftStart = nil; draftEnd = nil
            }
    }
    private func playhead(at position: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.9)).frame(width: 1, height: 55).offset(y: 8)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8)).foregroundStyle(.white)
        }.frame(width: 12, height: 64).offset(x: position - 6, y: 20).allowsHitTesting(false)
    }
    private func x(_ time: Double, width: CGFloat, lower: Double, span: Double) -> CGFloat {
        min(width, max(0, width * (time - lower) / span))
    }
}

private struct TimelineRuler: View {
    let lower: Double
    let duration: Double
    var body: some View {
        Canvas { context, size in
            let desired = duration / max(2, size.width / 85)
            let magnitude = pow(10, floor(log10(max(0.01, desired))))
            let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= desired } ?? magnitude * 10
            let first = ceil(lower / step) * step
            let count = Int(ceil(duration / step)) + 1
            for index in 0..<min(count, 100) {
                let time = first + Double(index) * step
                let position = (time - lower) / duration * size.width
                guard position <= size.width + 1 else { continue }
                var tick = Path(); tick.move(to: CGPoint(x: position, y: 17)); tick.addLine(to: CGPoint(x: position, y: 23))
                context.stroke(tick, with: .color(.white.opacity(0.23)), lineWidth: 0.5)
                let label = Text(timeLabel(time)).font(.system(size: 9, design: .monospaced)).foregroundColor(Color(white: 0.58))
                context.draw(label, at: CGPoint(x: min(size.width - 25, max(25, position)), y: 7))
            }
        }.accessibilityHidden(true)
    }
}

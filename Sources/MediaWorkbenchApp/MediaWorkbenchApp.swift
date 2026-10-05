import AppKit
import MediaCore
import SwiftUI

@main
struct MediaWorkbenchApp: App {
    @UIState private var model = WorkbenchModel()
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: icon) {
            NSApplication.shared.applicationIconImage = image
        }
    }
    var body: some Scene {
        Window("光集 · 调色与 Live", id: "workbench") {
            WorkbenchView(model: model).frame(minWidth: 1000, minHeight: 680).preferredColorScheme(.dark)
        }
        .defaultSize(width: 1380, height: 860)
        .windowStyle(.hiddenTitleBar).windowToolbarStyle(.unified)
        .commands {
            NativeControlsCommands()
            CommandGroup(replacing: .undoRedo) {
                Button("撤销编辑", action: model.undoEdit).keyboardShortcut("z").disabled(!model.canUndo || model.busy)
                Button("重做编辑", action: model.redoEdit).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo || model.busy)
            }
            CommandGroup(after: .saveItem) {
                Button("快照与版本…", action: model.openSnapshots).disabled(!model.loaded || model.busy)
                Button("拼图 Live…", action: model.openCollage).disabled(model.busy)
                Button("保存配方", action: model.saveDraft).keyboardShortcut("s").disabled(!model.loaded || model.busy)
            }
            CommandGroup(replacing: .newItem) {
                Button("打开素材…", action: model.openImage).keyboardShortcut("o").disabled(model.busy)
                Button("导入 LUT…", action: model.importLUT).disabled(model.busy)
            }
        }
        Window("光集 · 原生控件样板", id: "native-controls") {
            NativeControlsSample()
        }
        .defaultSize(width: 980, height: 700)
        .defaultLaunchBehavior(.suppressed)
        .windowToolbarStyle(.unified)
    }
}

private struct WorkbenchView: View {
    var model: WorkbenchModel
    @UIState private var showSidebar = true
    @UIState private var showInspector = true
    var body: some View {
        HStack(spacing: 0) {
            if showSidebar { SourceSidebar(model: model).transition(.move(edge: .leading).combined(with: .opacity)) }
            VStack(spacing: 0) {
                PreviewCanvas(model: model)
                if model.isVideo { MediaTimeline(model: model) }
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.mini) }
                    Text(model.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).help(model.message)
                    Spacer(minLength: 0)
                    if let progress = model.exportProgress { ProgressView(value: progress).frame(width: 80); Text("\(Int(progress * 100))%").font(.system(size: 10)).monospacedDigit() }
                    if model.canCancel { Button("取消", action: model.cancelOperation).buttonStyle(.plain).font(.system(size: 11)) }
                }.padding(.horizontal, 18).frame(height: 30).background(WorkbenchTheme.timeline)
            }.background(Color.black)
            if showInspector { InspectorView(model: model).transition(.move(edge: .trailing).combined(with: .opacity)) }
        }.background(WorkbenchTheme.panel).tint(WorkbenchTheme.accent)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { withAnimation(.easeOut(duration: 0.16)) { showSidebar.toggle() } } label: { Image(systemName: "sidebar.left") }
                        .help("显示或隐藏素材栏").accessibilityLabel("显示或隐藏素材栏")
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: model.openImage) { Label("打开", systemImage: "folder") }.disabled(model.busy).help("打开素材（⌘O）")
                }
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .principal) { toolbarTitle }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) { toolbarTitle }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: model.undoEdit) { Image(systemName: "arrow.uturn.backward") }
                        .help("撤销编辑（⌘Z）").accessibilityLabel("撤销编辑").disabled(!model.canUndo || model.busy)
                    Button(action: model.redoEdit) { Image(systemName: "arrow.uturn.forward") }
                        .help("重做编辑（⇧⌘Z）").accessibilityLabel("重做编辑").disabled(!model.canRedo || model.busy)
                    Button(action: model.openSnapshots) { Image(systemName: "clock.arrow.circlepath") }
                        .help("快照与版本").accessibilityLabel("快照与版本").disabled(!model.loaded || model.busy)
                    Button { model.comparing.toggle() } label: { Image(systemName: "square.lefthalf.filled") }
                        .help("对比原片（M）").accessibilityLabel("对比原片").keyboardShortcut("m", modifiers: [])
                        .tint(model.comparing ? WorkbenchTheme.accent : .primary).disabled(!model.loaded || model.busy)
                    Button { withAnimation(.easeOut(duration: 0.16)) { showInspector.toggle() } } label: { Image(systemName: "sidebar.right") }
                        .help("显示或隐藏检查器").accessibilityLabel("显示或隐藏检查器")
                    Button(action: model.export) { Label("导出", systemImage: "square.and.arrow.up") }
                        .disabled(!model.loaded || model.busy).help("导出编辑副本，保留原文件")
                }
            }
            .sheet(isPresented: Binding(get: { model.showingSnapshots }, set: { model.showingSnapshots = $0 })) { SnapshotSheet(model: model) }
            .sheet(isPresented: Binding(get: { model.showingCollage }, set: { model.showingCollage = $0 })) { CollageSheet(model: model) }
            .sheet(isPresented: Binding(get: { model.showingSync }, set: { model.showingSync = $0 })) { ColorSyncSheet(model: model) }
            .sheet(isPresented: Binding(get: { model.livePhoto != nil }, set: { if !$0 { model.livePhoto = nil } })) {
                VStack(spacing: 18) {
                    HStack { Text("Live Photo").font(.headline); Spacer(); Button("完成") { model.livePhoto = nil }.workstationButton() }
                    if let photo = model.livePhoto { LiveCanvas(photo: photo).frame(minWidth: 640, minHeight: 420) }
                    Text("按住画面播放 · Live 资源已保存 · 原片保留").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(24)
            }
    }
    private var toolbarTitle: some View {
        HStack(spacing: 7) {
            BrandMark().frame(width: 22, height: 22).accessibilityHidden(true)
            Text(model.url?.lastPathComponent ?? "光集")
                .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
        }.frame(maxWidth: 410)
            .help(model.url?.lastPathComponent ?? "调色与 Live 工作台")
    }
}

private struct SourceSidebar: View {
    var model: WorkbenchModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("素材").font(.system(size: 13, weight: .semibold)); Spacer()
                IconButton(title: "导入文件夹", icon: "folder.badge.plus", action: model.openFolder).disabled(model.busy)
                IconButton(title: "添加素材", icon: "plus", action: model.openImage).disabled(model.busy)
            }
            HStack {
                Button { model.showFavorites.toggle() } label: { Label(model.showFavorites ? "全部素材" : "收藏", systemImage: "star") }.buttonStyle(.plain)
                Spacer()
                Text("\(model.library.count)").foregroundStyle(.secondary)
            }.font(.system(size: 11))
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.library.filter { !model.showFavorites || $0.favorite }) { entry in
                        HStack(spacing: 6) {
                            Toggle("选择 \(entry.url.lastPathComponent)", isOn: Binding(get: { model.selectedSources.contains(entry.id) }, set: { selected in
                                if selected { model.selectedSources.insert(entry.id) } else { model.selectedSources.remove(entry.id) }
                            })).labelsHidden().toggleStyle(.checkbox).controlSize(.small)
                            Button { model.load(entry.url) } label: {
                                Label(entry.url.lastPathComponent, systemImage: entry.isVideo ? "video" : "photo")
                                    .font(.system(size: 11)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).foregroundStyle(entry.url == model.url ? WorkbenchTheme.accent : .primary).help(entry.url.path)
                            Button { model.toggleFavorite(entry) } label: {
                                Image(systemName: entry.favorite ? "star.fill" : "star").font(.system(size: 10)).foregroundStyle(entry.favorite ? WorkbenchTheme.accent : .secondary)
                            }.buttonStyle(.plain).accessibilityLabel(entry.favorite ? "取消收藏" : "收藏素材")
                        }.padding(.horizontal, 5).padding(.vertical, 7)
                            .background(entry.url == model.url ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .disabled(model.busy)
                    }
                }
            }
            if !model.library.isEmpty {
                HStack {
                    Text("已选 \(model.selectedSources.count) 项")
                    Spacer()
                    Button("全选") { model.selectedSources = Set(model.library.filter { !model.showFavorites || $0.favorite }.map(\.id)) }.buttonStyle(.plain)
                    Button("清空") { model.selectedSources = [] }.buttonStyle(.plain)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                Button("同步调色…") { model.showingSync = true }.workstationButton()
                    .disabled(!model.loaded || model.busy || model.selectedSources.subtracting([model.url?.path ?? ""]).isEmpty)
                Button("拼图 Live…", action: model.openCollage).workstationButton().disabled(model.busy || !(1...3).contains(model.selectedSources.count))
                Menu("导出所选…") {
                    Button("按素材类型导出") { model.exportSelected() }
                    Button("只制作有效 Live 片段") { model.exportSelected(liveOnly: true) }
                }.menuStyle(.borderlessButton).font(.system(size: 11)).disabled(model.busy || model.selectedSources.isEmpty)
                if !model.lastBatch.isEmpty { Button("撤回上次同步", action: model.undoBatch).buttonStyle(.plain).font(.system(size: 11)).disabled(model.busy) }
            }
            if let info = model.metadata {
                WorkbenchTheme.hairline.frame(height: 1)
                Text(model.url?.lastPathComponent ?? "").font(.system(size: 11, weight: .medium)).lineLimit(2)
                detail("尺寸", "\(info.displayWidth) × \(info.displayHeight)")
                if model.isVideo { detail("时长", timeLabel(model.duration)); detail("帧率", String(format: "%.2f fps", info.nominalFrameRate ?? 0)) }
                detail("色彩", model.sourceHDR ? "HDR" : "SDR")
            }
            Label(model.draftStatus, systemImage: "lock").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.horizontal, 14).padding(.vertical, 18).frame(width: 220).frame(maxHeight: .infinity)
            .background { SidebarMaterial().overlay(WorkbenchTheme.panel.opacity(0.35)) }
            .overlay(alignment: .trailing) { WorkbenchTheme.hairline.frame(width: 1) }
    }
    private func detail(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(minLength: 2); Text(value).monospacedDigit() }.font(.system(size: 10))
    }
}

private struct PreviewCanvas: View {
    var model: WorkbenchModel
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let player = model.player { VideoCanvas(player: player) }
                else if let frame = model.frame {
                    HDRImageCanvas(frame: frame, comparing: model.comparing, hdr: model.hdrPreview) { model.screenHeadroom = $0 }
                } else {
                    VStack(spacing: 14) {
                        BrandEmptyIllustration().frame(width: 240, height: 160)
                        Text("把光，收进画面。").font(.system(size: 20, weight: .medium)).foregroundStyle(.primary)
                        Text("图片、视频与 Live · 调色与片段制作").font(.system(size: 12))
                        Button("打开素材…", action: model.openImage).workstationButton().disabled(model.busy)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.loaded && model.grid {
                GeometryReader { bounds in
                    let aspect = mediaAspectRatio
                    let width = min(bounds.size.width, bounds.size.height * aspect)
                    let height = width / aspect
                    let origin = CGPoint(x: (bounds.size.width - width) / 2, y: (bounds.size.height - height) / 2)
                    Path { path in
                        for part in 1...2 {
                            let x = origin.x + width * CGFloat(part) / 3, y = origin.y + height * CGFloat(part) / 3
                            path.move(to: CGPoint(x: x, y: origin.y)); path.addLine(to: CGPoint(x: x, y: origin.y + height))
                            path.move(to: CGPoint(x: origin.x, y: y)); path.addLine(to: CGPoint(x: origin.x + width, y: y))
                        }
                    }.stroke(.white.opacity(0.3), lineWidth: 0.5)
                }.allowsHitTesting(false)
            }
            if model.loaded {
                Text(model.comparing ? "原片" : model.previewLabel).font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 6).workstationGlass().padding(16).allowsHitTesting(false)
            }
        }
    }
    private var mediaAspectRatio: CGFloat {
        if let frame = model.frame {
            let extent = model.comparing ? frame.original.extent : frame.image.extent
            return max(0.01, extent.width / max(1, extent.height))
        }
        if let info = model.metadata {
            if !model.comparing, let size = try? ColorPipeline.geometrySize(width: info.displayWidth, height: info.displayHeight, edits: model.edits) { return max(0.01, size.width / max(1, size.height)) }
            return max(0.01, CGFloat(info.displayWidth) / CGFloat(max(1, info.displayHeight)))
        }
        return 1
    }
}

private enum InspectorTab: String, CaseIterable { case color = "调色", geometry = "画面", audio = "声音" }

private struct InspectorView: View {
    @Bindable var model: WorkbenchModel
    @UIState private var tab = InspectorTab.color
    var body: some View {
        VStack(spacing: 0) {
            SlidingSegmentedControl(
                options: InspectorTab.allCases.filter { model.isVideo || $0 != .audio },
                selection: Binding(get: { tab }, set: { tab = $0 }),
                title: { $0.rawValue }
            ).padding(.horizontal, 16).padding(.vertical, 12)
            WorkbenchTheme.hairline.frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if tab == .color { colorControls }
                    else if tab == .geometry { geometryControls }
                    else { audioControls }
                }.padding(20)
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            HStack {
                Label("\(model.isVideo ? "MOV" : "PNG") · \(model.isVideo && model.hdrEffect ? "HDR 效果" : "SDR")副本", systemImage: "square.and.arrow.up").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                IconButton(title: "恢复原片画面", icon: "arrow.counterclockwise", action: model.reset).disabled(!model.loaded || model.busy)
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }.frame(width: 288).frame(maxHeight: .infinity).background(WorkbenchTheme.panel)
            .overlay(alignment: .leading) { WorkbenchTheme.hairline.frame(width: 1) }
            .onChange(of: model.isVideo) { _, video in if !video && tab == .audio { tab = .color } }
    }
    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 6) {
                RGBHistogramView(histogram: model.histogram).frame(height: 84)
                HStack {
                    Text(model.histogramLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: model.refreshHistogram) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("更新当前帧直方图")
                    InfoButton(text: "统计当前 SDR 显示画面的 RGB 分布。视频仅分析所选帧，不分析整段；HDR 会先映射到 SDR，因此边缘峰值不能直接当成源素材过曝。")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                PanelHeading(title: "预览", info: "HDR 原片按显示器能力播放。创意 LUT 默认输出 SDR；开启 HDR 效果会扩展高光亮度，使用 10-bit HLG 和增益图封面保存。该效果不恢复拍摄时丢失的高光。")
                Toggle("HDR 原片", isOn: $model.hdrPreview).toggleStyle(.switch).controlSize(.small).font(.system(size: 13))
                    .disabled(!model.loaded || model.busy)
                if model.sourceHDR { Text(model.previewLabel).font(.system(size: 10)).foregroundStyle(.secondary) }
                if model.isVideo {
                    Toggle("HDR 效果（实验）", isOn: $model.hdrEffect).toggleStyle(.switch).controlSize(.small).font(.system(size: 13))
                        .disabled(model.busy)
                        .help("扩展 SDR 高光亮度，导出 10-bit HLG 视频和增益图 Live 封面；无法找回拍摄时丢失的高光。")
                    if model.hdrEffect { Text("扩展高光亮度 · HEVC 10-bit HLG").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                PanelHeading(title: "创意 LUT", info: "LUT 把输入颜色映射到另一组颜色。导入后按作者说明选择 sRGB 或 Rec.709 色彩空间；相机 Log 输入需先完成匹配的转换。强度控制原色与风格的混合。")
                HStack(spacing: 6) {
                    preset("原色", choice: "none")
                    preset("暖调", choice: CreativeLUT.warm.id.uuidString)
                    preset("柔和", choice: CreativeLUT.soft.id.uuidString)
                }
                if let lut = model.importedLUT { preset(lut.name, choice: lut.id.uuidString) }
                Button(action: model.importLUT) { Label("导入 LUT…", systemImage: "plus") }.workstationButton().foregroundStyle(.secondary).disabled(model.busy)
                if let lut = model.importedLUT, model.selectedLUT?.id == lut.id {
                    Picker("LUT 色彩空间", selection: Binding(get: { lut.encoding }, set: model.setImportedLUTEncoding)) {
                        ForEach(LUTEncoding.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).font(.system(size: 13)).disabled(model.busy)
                }
                ParameterControl(title: "强度", value: Binding(get: { model.strength * 100 }, set: { model.strength = $0 / 100 }), range: 0...100, suffix: "%", resetValue: 100, onEditingChanged: model.beginEditing)
                    .disabled(model.selectedLUT == nil || model.busy)
            }
            ForEach(AdjustmentGroup.allCases, id: \.self) { group in
                AdjustmentSection(model: model, group: group)
            }
        }
    }
    private func preset(_ title: String, choice: String) -> some View {
        Button { model.lutChoice = choice } label: {
            Text(title).font(.system(size: 13, weight: model.lutChoice == choice ? .semibold : .regular)).lineLimit(1)
                .foregroundStyle(model.lutChoice == choice ? WorkbenchTheme.accent : Color.primary)
                .frame(maxWidth: .infinity)
        }.workstationButton().disabled(!model.loaded || model.busy).accessibilityLabel("\(title)风格")
            .accessibilityAddTraits(model.lutChoice == choice ? [.isSelected] : [])
    }
    private var geometryControls: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeading(title: "水平校正", info: "旋转画面后会裁切边缘，以避免黑边。自动调正通过地平线识别建议角度，当前支持静态图片。")
                ParameterControl(title: "角度", value: $model.degrees, range: -10...10, step: 0.05, suffix: "°", decimals: 2, onEditingChanged: model.beginEditing)
                    .disabled(!model.loaded || model.busy)
                HStack {
                    if !model.isVideo { Button("自动调正", action: model.autoStraighten).workstationButton() }
                    Button("归零") { model.degrees = 0 }.workstationButton().foregroundStyle(.secondary)
                }.disabled(!model.loaded || model.busy)
                HStack {
                    Button { model.geometry.quarterTurns = (model.geometry.quarterTurns + 1) % 4 } label: { Label("旋转 90°", systemImage: "rotate.left") }.workstationButton()
                    Button { model.geometry.mirrored.toggle() } label: { Label("镜像", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }.workstationButton()
                }.disabled(!model.loaded || model.busy)
                Picker("裁切画幅", selection: $model.geometry.aspectRatio) {
                    Text("原始比例").tag(0.0); Text("1:1").tag(1.0); Text("4:3").tag(4.0/3); Text("3:2").tag(1.5)
                    Text("16:9").tag(16.0/9); Text("9:16").tag(9.0/16)
                }.font(.system(size: 12)).disabled(!model.loaded || model.busy)
                ParameterControl(title: "裁切保留", value: Binding(get: { model.geometry.cropScale * 100 }, set: { model.geometry.cropScale = $0 / 100 }), range: 25...100, suffix: "%", resetValue: 100, onEditingChanged: model.beginEditing)
                    .disabled(!model.loaded || model.busy)
                DisclosureGroup("裁切位置") {
                    ParameterControl(title: "横向位置", value: $model.geometry.horizontal, range: -100...100, onEditingChanged: model.beginEditing)
                    ParameterControl(title: "纵向位置", value: $model.geometry.vertical, range: -100...100, onEditingChanged: model.beginEditing)
                    Button("恢复画幅") { model.geometry = .init() }.buttonStyle(.plain).font(.system(size: 11))
                }.font(.system(size: 12)).disabled(!model.loaded || model.busy)
                Toggle("参考网格", isOn: $model.grid).toggleStyle(.switch).controlSize(.small).font(.system(size: 13)).disabled(!model.loaded)
            }
            if model.isVideo {
                VStack(alignment: .leading, spacing: 12) {
                    PanelHeading(title: "Live 片段", info: "Live 输出为 0.5–3 秒。拖动片段中间整体平移，拖动两端裁切；菱形选择封面。2× 速度可把原片 6 秒制作成 3 秒 Live。背景音乐保留原节奏。")
                    Text("拖动片段中间移动整个选取范围").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack { Text("原片范围"); Spacer(); Text(String(format: "%.2f 秒", model.clip.sourceDuration)).monospacedDigit() }.font(.system(size: 12))
                    ParameterControl(title: "速度", value: $model.playbackSpeed, range: 0.5...4, step: 0.05, suffix: "×", decimals: 2, resetValue: 1, onEditingChanged: model.speedEditingChanged)
                        .disabled(model.busy)
                    HStack { Text("输出长度"); Spacer(); Text(String(format: "%.2f 秒", model.clip.outputDuration)).monospacedDigit() }.font(.system(size: 12))
                    Button("压缩为 3 秒", action: model.fitLiveSpeed).workstationButton().disabled(model.busy || model.clip.sourceDuration < 1.5)
                    Button("以当前位置选取 3 秒 Live", action: model.liveRange).workstationButton().disabled(model.busy)
                }
            }
        }
    }
    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { PanelHeading(title: "原声"); IconButton(title: "静音原声", icon: model.originalVolume == 0 ? "speaker.slash" : "speaker.wave.2", active: model.originalVolume == 0) { model.originalVolume = model.originalVolume == 0 ? 1 : 0 } }
                ParameterControl(title: "原声音量", value: Binding(get: { Double(model.originalVolume) * 100 }, set: { model.originalVolume = Float($0 / 100) }), range: 0...100, suffix: "%", resetValue: 100, onEditingChanged: model.beginEditing)
            }
            VStack(alignment: .leading, spacing: 12) {
                PanelHeading(title: "背景音乐", info: "音乐从片段开头播放，按片段长度截取；当前不循环、不改变原音乐文件。")
                if let music = model.musicURL {
                    HStack { Text(music.lastPathComponent).font(.system(size: 12)).lineLimit(2); Spacer(); IconButton(title: "移除背景音乐", icon: "xmark") { model.musicURL = nil } }
                    ParameterControl(title: "BGM 音量", value: Binding(get: { Double(model.musicVolume) * 100 }, set: { model.musicVolume = Float($0 / 100) }), range: 0...100, suffix: "%", resetValue: 50, onEditingChanged: model.beginEditing)
                    Button("更换音乐…", action: model.chooseMusic).workstationButton().foregroundStyle(.secondary)
                } else { Button(action: model.chooseMusic) { Label("添加音乐…", systemImage: "plus") }.workstationButton() }
            }
        }.disabled(model.busy)
    }
}

private struct AdjustmentSection: View {
    var model: WorkbenchModel
    let group: AdjustmentGroup
    @UIState private var expanded = true
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 12) {
                HStack {
                    Text(group == .color ? "色温与色调为相对偏移" : group == .detail ? "空间滤镜 · 视频为单帧处理" : "0 为原片状态").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("归零") { model.resetGroup(group) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WorkbenchTheme.accent)
                }.padding(.top, 8)
                ForEach(AdjustmentParameter.allCases.filter { $0.group == group }) { parameter in
                    ParameterControl(title: parameter.title,
                        value: Binding(get: { model.adjustments[parameter] }, set: { model.adjustments[parameter] = $0 }),
                        range: parameter.range, step: parameter == .exposure ? 0.05 : 1,
                        suffix: parameter == .exposure ? "EV" : "", decimals: parameter == .exposure ? 2 : 0,
                        onEditingChanged: model.beginEditing, info: parameter.explanation)
                }
            }
        } label: { Text(group.rawValue).font(.system(size: 13, weight: .semibold)) }
        .disabled(!model.loaded || model.busy)
        .onAppear { if group == .detail { expanded = false } }
    }
}

private struct ColorSyncSheet: View {
    var model: WorkbenchModel
    @UIState private var groups: Set<AdjustmentGroup> = [.light, .color]
    @UIState private var includeLUT = true
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("同步调色").font(.headline); Spacer(); Button("取消") { model.showingSync = false }.workstationButton() }
            Text("将当前素材的选定参数复制到另外 \(model.selectedSources.subtracting([model.url?.path ?? ""]).count) 项素材。未勾选参数、片段、封面、速度与声音保留。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(AdjustmentGroup.allCases, id: \.self) { group in
                Toggle(group.rawValue, isOn: Binding(get: { groups.contains(group) }, set: { if $0 { groups.insert(group) } else { groups.remove(group) } }))
            }
            Toggle("创意 LUT 与强度", isOn: $includeLUT)
            Text("复制相同数值。相机 Log 输入应先匹配转换；这一步不自动识别相机模式。离线或已变化的原件跳过并计数。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Spacer(); Button("应用到所选素材") { model.synchronize(groups: groups, includeLUT: includeLUT) }.workstationPrimaryButton().disabled(groups.isEmpty && !includeLUT) }
        }.padding(24).frame(width: 470)
    }
}

private struct RGBHistogramView: View {
    let histogram: PreviewHistogram?
    var body: some View {
        Canvas { context, size in
            guard let histogram else { return }
            let colors: [Color] = [.red, .green, .blue]
            for (index, values) in histogram.channels.enumerated() {
                var area = Path()
                area.move(to: CGPoint(x: 0, y: size.height))
                for (bin, value) in values.enumerated() {
                    area.addLine(to: CGPoint(x: size.width * Double(bin) / Double(values.count - 1), y: size.height * (1 - sqrt(value) * 0.95)))
                }
                area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
                context.fill(area, with: .color(colors[index].opacity(0.24)))
                context.stroke(area, with: .color(colors[index].opacity(0.6)), lineWidth: 0.7)
            }
        }.background(Color.black.opacity(0.18))
         .accessibilityLabel("当前 SDR 画面 RGB 直方图")
    }
}

private struct SnapshotSheet: View {
    @Bindable var model: WorkbenchModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("快照与版本").font(.headline); Spacer(); Button("完成") { model.showingSnapshots = false }.workstationButton() }
            Text("自动保存当前配方；快照保留指定版本，重启后仍可恢复。这里只保存参数和 LUT 引用，不复制原片。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                TextField("版本名称，例如：自然暖调", text: $model.snapshotName)
                Button("保存当前版本", action: model.saveSnapshot).workstationButton()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.savedSnapshots) { value in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(value.name).font(.system(size: 13, weight: .medium))
                                Text(value.record.savedAt.formatted(date: .numeric, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("恢复") { model.restoreSavedSnapshot(value) }.workstationButton()
                        }.padding(.vertical, 10)
                        WorkbenchTheme.hairline.frame(height: 1)
                    }
                    if model.savedSnapshots.isEmpty { Text("尚未保存快照").font(.system(size: 12)).foregroundStyle(.secondary).padding(30) }
                }
            }.frame(height: 240)
            Text("显示最近 50 个快照；原件或 Live 动态部分变化时拒绝误套旧版本。恢复操作可以撤销。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 520)
    }
}

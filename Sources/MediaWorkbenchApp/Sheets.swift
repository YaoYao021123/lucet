import AppKit
import MediaCore
import Photos
import SwiftUI

struct SheetContent: View {
    let app: AppModel
    let sheet: ActiveSheet
    var body: some View {
        content.tint(WorkbenchTheme.accent)
    }
    @ViewBuilder private var content: some View {
        switch sheet {
        case .export(let target): ExportOptionsSheet(app: app, target: target)
        case .sync: SyncSheet(app: app)
        case .snapshots: SnapshotSheet(app: app)
        case .collage: CollageSheet(app: app)
        case .savePreset: SavePresetSheet(app: app)
        case .shortcuts: ShortcutsSheet(app: app)
        case .tutorSettings: TutorSettingsSheet(tutor: app.tutor)
        case .livePreview(let resources): LivePreviewSheet(app: app, resources: resources)
        }
    }
}

private struct SheetHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

// MARK: - Export options

struct ExportOptionsSheet: View {
    let app: AppModel
    let target: ExportTarget
    @UIState private var settings = ExportSettings()

    private var entries: [LibraryEntry] { target == .current ? app.currentEntry.map { [$0] } ?? [] : app.library.actionTargets }
    private var hasImages: Bool { target == .current ? !app.editor.isVideo : entries.contains { !$0.isVideo } }
    private var hasVideos: Bool { target == .current ? app.editor.isVideo : entries.contains { $0.isVideo || $0.hasLiveCompanion } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: target == .current ? "导出副本" : "导出 \(entries.count) 项",
                        subtitle: "导出会在后台进行，你可以继续浏览和编辑。原片从不修改。")
            Form {
                Section {
                    Picker("保存到", selection: $settings.destination) {
                        ForEach(ExportDestination.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(settings.destination == .photos
                         ? "直接存入 Mac 的「照片」，开启 iCloud 照片后会同步到 iPhone。Live 片段会存为真正的 Live Photo。"
                         : "存为文件，可以选择位置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if hasImages {
                    Section("照片") {
                        Picker("格式", selection: $settings.image.format) {
                            ForEach(ImageExportOptions.Format.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if settings.image.format.isLossy {
                            LabeledContent("质量") {
                                HStack {
                                    Slider(value: $settings.image.quality, in: 0.5...1)
                                    Text("\(Int(settings.image.quality * 100))").monospacedDigit().frame(width: 30)
                                }
                            }
                        }
                        Picker("尺寸", selection: Binding(get: { settings.image.maxLongEdge ?? 0 }, set: { settings.image.maxLongEdge = $0 == 0 ? nil : $0 })) {
                            Text("原始尺寸").tag(0)
                            Text("长边 4096 px").tag(4096)
                            Text("长边 2048 px").tag(2048)
                            Text("长边 1080 px（社交平台）").tag(1080)
                        }
                        Toggle("保留拍摄信息（时间、相机、镜头）", isOn: $settings.image.keepMetadata)
                        Toggle("移除位置信息", isOn: $settings.image.removeLocation).disabled(!settings.image.keepMetadata)
                    }
                }
                if hasVideos {
                    Section("视频") {
                        Picker("编码", selection: $settings.codec) {
                            ForEach(VideoCodecChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        if target == .selection {
                            Toggle("只导出有效的 Live 片段（0.5–3 秒）", isOn: $settings.liveOnly)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("取消") { app.sheet = nil }.keyboardShortcut(.cancelAction)
                Button(settings.destination == .photos ? "存到「照片」" : target == .current ? "选择位置…" : "选择文件夹…") {
                    app.exportSettings = settings
                    app.confirmExport(target)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear { settings = app.exportSettings }
    }
}

// MARK: - Sync

struct SyncSheet: View {
    let app: AppModel
    /// Exposure usually differs shot to shot, so it starts unchecked (as do detail and effects).
    @UIState private var sections: Set<AdjustmentSection> = [.tone, .whiteBalance, .color]
    @UIState private var stages: Set<GradeStage> = [.wheels, .curves, .hsl]
    @UIState private var includeLUT = true

    var body: some View {
        let count = app.library.selection.subtracting([app.library.currentID ?? ""]).count
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "同步调色", subtitle: "把当前素材的所选调色复制到另外 \(count) 项。曝光默认不同步（每张往往不同）；裁切、片段、封面、速度与声音保持各自设置。")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AdjustmentSection.allCases, id: \.self) { section in
                    Toggle(isOn: Binding(get: { sections.contains(section) }, set: { if $0 { sections.insert(section) } else { sections.remove(section) } })) {
                        HStack(spacing: 6) {
                            Text(section.title)
                            Text(section.parameters.map(\.title).joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .help(section.summary)
                }
                ForEach([GradeStage.wheels, .curves, .hsl], id: \.self) { stage in
                    Toggle(stage == .hsl ? "HSL 色彩混合" : stage.title, isOn: Binding(get: { stages.contains(stage) }, set: { if $0 { stages.insert(stage) } else { stages.remove(stage) } }))
                }
                Toggle("风格 LUT 与强度", isOn: $includeLUT)
            }
            .toggleStyle(.checkbox)
            Text("离线或已被修改的原片会跳过并计数。同步后可在提示中一键撤回。").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { app.sheet = nil }.keyboardShortcut(.cancelAction)
                Button("应用到 \(count) 项") {
                    app.sheet = nil
                    app.synchronize(sections: sections, includeLUT: includeLUT, stages: stages)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0 || (sections.isEmpty && stages.isEmpty && !includeLUT))
            }
        }
        .padding(22).frame(width: 440)
    }
}

// MARK: - Snapshots

struct SnapshotSheet: View {
    let app: AppModel
    @UIState private var name = ""
    @UIState private var snapshots: [SavedSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "快照与版本", subtitle: "快照保存一个命名版本，重启后仍可恢复。只保存参数，不复制原片。")
            HStack {
                TextField("版本名称，例如：自然暖调", text: $name).textFieldStyle(.roundedBorder)
                Button("保存当前版本") { app.editor.saveSnapshot(named: name); name = ""; snapshots = app.editor.snapshots() }
            }
            List(snapshots) { value in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.name)
                        Text(value.record.savedAt.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("恢复") { app.editor.restoreSnapshot(value); app.sheet = nil }
                }
            }
            .frame(height: 220)
            .overlay { if snapshots.isEmpty { Text("尚未保存快照").foregroundStyle(.secondary) } }
            HStack { Spacer(); Button("完成") { app.sheet = nil }.keyboardShortcut(.defaultAction) }
        }
        .padding(22).frame(width: 480)
        .onAppear { snapshots = app.editor.snapshots() }
    }
}

// MARK: - Presets

struct SavePresetSheet: View {
    let app: AppModel
    @UIState private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "存为预设", subtitle: "保存当前的基础调整、色轮、曲线、HSL 与 LUT，可套用到任意照片或视频。")
            TextField("预设名称", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { app.sheet = nil }.keyboardShortcut(.cancelAction)
                Button("保存") { app.savePreset(named: name); app.sheet = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 400)
    }
}

// MARK: - Shortcuts

struct ShortcutsSheet: View {
    let app: AppModel
    private let groups: [(String, [(String, String)])] = [
        ("浏览", [("G / E", "浏览网格 / 编辑"), ("↑ ↓ ← →", "上一项 / 下一项"), ("⏎ 或 空格", "打开所选"),
                 ("0 – 5", "评级"), ("P / X / U", "选用 / 排除 / 取消标记"), ("⌘ / ⇧ 点按", "多选"), ("Tab", "隐藏 / 显示侧栏")]),
        ("编辑", [("A", "自动调整"), ("\\ 或 M", "对比原片"), ("Y", "左右分屏对比"), ("J", "显示高光 / 暗部溢出"), ("Z 或 空格", "适合窗口 ↔ 100%"),
                 ("⌘0 / ⌘1 / ⌘+ / ⌘−", "适合 / 实际像素 / 放大 / 缩小"), ("⌘Z / ⇧⌘Z", "撤销 / 重做"),
                 ("⇧⌘C / ⇧⌘V", "拷贝 / 粘贴调色设置"), ("双击参数名", "恢复默认")]),
        ("视频", [("空格", "播放 / 暂停"), ("← →", "逐帧"), ("I / O", "设置入点 / 出点"), ("C", "把播放头设为封面")]),
        ("其他", [("⌘E / ⇧⌘E", "导出当前 / 导出所选"), ("⌘S", "立即保存配方"), ("?", "显示本页")])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "键盘快捷键")
            HStack(alignment: .top, spacing: 28) {
                ForEach(0..<2, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groups.indices.filter { $0 % 2 == column }, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(groups[index].0).font(.headline)
                                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                                    ForEach(groups[index].1, id: \.0) { item in
                                        GridRow {
                                            Text(item.0).font(.callout.monospaced())
                                            Text(item.1).font(.callout).foregroundStyle(.secondary).fixedSize()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack { Spacer(); Button("完成") { app.sheet = nil }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
    }
}

// MARK: - Live preview

struct LivePreviewSheet: View {
    let app: AppModel
    let resources: LivePhotoResources
    @UIState private var photo: PHLivePhoto?
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Live Photo").font(.headline)
                Spacer()
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([resources.imageURL]) }
                Button("完成") { app.sheet = nil }.keyboardShortcut(.defaultAction)
            }
            ZStack {
                Color.black
                if let photo { LiveCanvas(photo: photo) } else { ProgressView() }
            }
            .frame(minWidth: 640, minHeight: 420)
            Text("按住画面播放").font(.callout).foregroundStyle(.secondary)
        }
        .padding(22)
        .task { photo = try? await LivePhotoPipeline.load(imageURL: resources.imageURL, videoURL: resources.videoURL) }
    }
}

// MARK: - Ask settings

struct TutorSettingsSheet: View {
    let tutor: TutorModel
    @UIState private var keyInput = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("问问这张照片 · 设置").font(.title3.weight(.semibold))
                Text("由 Anthropic 的 Claude 模型回答关于照片的问题，讲解会结合画面、参数和你的学习水平。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Form {
                Section {
                    Toggle("启用 AI 提问", isOn: Binding(get: { tutor.settings.enabled }, set: { tutor.settings.enabled = $0 }))
                }
                Section("发送的内容") {
                    Toggle("附带预览图（最长边 1024 px 的 JPEG，不含拍摄与位置信息）",
                           isOn: Binding(get: { tutor.settings.sendPreview }, set: { tutor.settings.sendPreview = $0 }))
                    Text("每次提问还会发送：画面统计、当前调色参数、你选择的水平与兴趣。原片不会上传；只有你点「提问」时才会发送。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("API 密钥") {
                    if tutor.hasKey {
                        HStack {
                            Label("已保存在钥匙串中", systemImage: "key.fill")
                            Spacer()
                            Button("移除", role: .destructive, action: tutor.removeKey)
                        }
                    } else {
                        HStack {
                            SecureField("sk-ant-…", text: $keyInput)
                            Button("保存") { tutor.saveKey(keyInput); keyInput = "" }
                                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Text("在 console.anthropic.com 创建密钥。费用按你的 Anthropic 账户计费；中国大陆网络可能无法直接访问。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("模型") {
                    Picker("模型", selection: Binding(get: { tutor.settings.model }, set: { tutor.settings.model = $0 })) {
                        ForEach(ClaudePhotoTutor.models) { Text($0.title).tag($0.id) }
                    }
                    if let option = ClaudePhotoTutor.models.first(where: { $0.id == tutor.settings.model }) {
                        Text(option.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(22)
        .frame(width: 520)
    }
}

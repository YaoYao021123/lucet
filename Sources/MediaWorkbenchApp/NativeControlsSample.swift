import SwiftUI

/// A real system-rendered reference, isolated from media and export state.
struct NativeControlsCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("开发") {
            Button("原生控件样板…") { openWindow(id: "native-controls") }
        }
    }
}

struct NativeControlsSample: View {
    @UIState private var strength = 60.0
    @UIState private var degrees = 2.0
    @UIState private var volume = 35.0
    @UIState private var disabledValue = 60.0
    @UIState private var hdr = true
    @UIState private var tab = "调色"
    @UIState private var dark = true
    @UIState private var status = "样板参数独立保存于此窗口，不处理素材。"
    @UIState private var showSidebar = true
    @UIState private var comparing = false

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                VStack(alignment: .leading, spacing: 22) {
                    Text("原生控件").font(.headline)
                    Label("参数与声音", systemImage: "slider.horizontal.3")
                    Label("按钮与工具栏", systemImage: "rectangle.topthird.inset.filled")
                    Spacer()
                    Text("SwiftUI / AppKit\n当前系统实际渲染")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(width: 185).frame(maxHeight: .infinity, alignment: .top)
                .background { SidebarMaterial() }
                Divider()
            }
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("参数与控件样板").font(.title2.weight(.semibold))
                        Text("滑块头、轨道、按钮底座由系统绘制。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("深色", isOn: $dark).toggleStyle(.switch).controlSize(.small)
                }
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("实际参数控件").font(.headline)
                        ParameterControl(title: "LUT 强度", value: $strength, range: 0...100, suffix: "%", resetValue: 100)
                        ParameterControl(title: "角度", value: $degrees, range: -10...10, step: 0.05, suffix: "°", decimals: 2)
                        ParameterControl(title: "原声音量", value: $volume, range: 0...100, suffix: "%", resetValue: 100)
                        ParameterControl(title: "禁用状态", value: $disabledValue, range: 0...100, suffix: "%", resetValue: 100)
                            .disabled(true)
                        Toggle("HDR 原片", isOn: $hdr).toggleStyle(.switch).controlSize(.small)
                        Text("拖动、方向键、直接输入数值；右键恢复默认值。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 22) {
                        Text("原生按钮与平滑切换").font(.headline)
                        SlidingSegmentedControl(options: ["调色", "画面", "声音"], selection: $tab, title: { $0 })
                        Text("点击或拖动切换，松手吸附；减少动态效果时不播放过渡。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            Button("导出…") { status = "样板动作：导出。未写入任何文件。" }
                                .workstationButton()
                            Button("选取 3 秒") { status = "样板动作：选取片段。" }
                                .workstationButton()
                        }
                        HStack(spacing: 14) {
                            Button { comparing.toggle() } label: {
                                Image(systemName: "square.lefthalf.filled").font(.system(size: 16)).frame(width: 22, height: 22)
                            }.workstationButton(shape: .circle).help("原片对比").accessibilityLabel("样板原片对比")
                            Button { volume = volume == 0 ? 35 : 0 } label: {
                                Image(systemName: volume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 16)).frame(width: 22, height: 22)
                            }.workstationButton(shape: .circle).help("静音").accessibilityLabel("样板静音")
                            Button {} label: { Image(systemName: "square.and.arrow.up").font(.system(size: 16)).frame(width: 22, height: 22) }
                                .workstationButton(shape: .circle).disabled(true).accessibilityLabel("禁用的导出按钮")
                        }.font(.system(size: 16, weight: .regular))
                        liveButton
                        Divider()
                        Text("尺寸对照").font(.headline)
                        HStack(spacing: 14) {
                            Button("Small") { status = "Small：系统小型按钮。" }.controlSize(.small)
                            Button("Regular") { status = "Regular：系统常规按钮。" }.controlSize(.regular)
                        }
                        Text("Small / Regular 是系统规格，不手绘固定圆角或图标底座。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Text(status).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(tab) · \(comparing ? "原片" : "编辑")").monospacedDigit()
                }.font(.caption)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(WorkbenchTheme.accent)
        .preferredColorScheme(dark ? .dark : .light)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help("显示或隐藏样板侧栏").accessibilityLabel("显示或隐藏样板侧栏")
            }
            ToolbarItem(placement: .principal) { Text("原生控件样板").font(.headline) }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { comparing.toggle() } label: { Image(systemName: "square.lefthalf.filled") }
                    .help("原片对比").accessibilityLabel("工具栏原片对比")
                Button { status = "样板工具栏导出。未写入任何文件。" } label: {
                    Image(systemName: "square.and.arrow.up")
                }.help("导出…").accessibilityLabel("工具栏导出")
            }
        }
    }

    private var liveButton: some View {
        Button("制作 Live") { status = "样板动作：制作 Live。未导出任何素材。" }
            .workstationPrimaryButton()
    }
}

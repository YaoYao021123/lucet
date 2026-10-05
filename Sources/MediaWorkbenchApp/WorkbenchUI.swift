import AppKit
import SwiftUI

typealias UIState<Value> = SwiftUI.State<Value>

enum WorkbenchTheme {
    static let accent = Color(red: 0.80, green: 0.71, blue: 0.48)
    static let panel = Color(white: 0.115)
    static let canvas = Color(white: 0.07)
    static let well = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.08)
    static let pick = Color(red: 0.55, green: 0.82, blue: 0.55)
    static let reject = Color(red: 0.92, green: 0.42, blue: 0.38)
}

/// One-line parameter: label · slider · value. Double-click the label (or
/// right-click) to reset. Equatable, so dragging one slider never redraws the others.
struct ParameterRow: View, @MainActor Equatable {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var decimals = 0
    var suffix = ""
    var neutral: Double = 0
    var help: String?
    var labelWidth: CGFloat = 62
    let onChange: (Double) -> Void
    var onEditing: (Bool) -> Void = { _ in }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.value == rhs.value && lhs.range == rhs.range && lhs.step == rhs.step
            && lhs.decimals == rhs.decimals && lhs.suffix == rhs.suffix && lhs.neutral == rhs.neutral
    }

    @UIState private var position: Double?
    @UIState private var dragging = false
    @Environment(\.isEnabled) private var enabled

    private func clamp(_ next: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, (next / step).rounded() * step))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(value == neutral ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { reset() }
                .help((help.map { $0 + "\n" } ?? "") + "双击名称恢复默认")
            slider
            HStack(spacing: 2) {
                TextField("", value: Binding(get: { value }, set: { next in if next.isFinite { onChange(clamp(next)) } }),
                          format: .number.precision(.fractionLength(decimals)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("\(title)数值")
                Text(suffix).font(.caption).foregroundStyle(.tertiary).frame(width: 16, alignment: .leading)
            }
            .frame(width: 58)
        }
        .font(.callout)
        .frame(height: 22)
        .contextMenu { Button("恢复默认值") { reset() } }
        .opacity(enabled ? 1 : 0.5)
    }

    @ViewBuilder private var slider: some View {
        let binding = Binding(get: { position ?? value }, set: { next in
            position = next
            let rounded = clamp(next)
            if rounded != value { onChange(rounded) }
        })
        Group {
            if #available(macOS 26, *) {
                Slider(value: binding, in: range, neutralValue: range.lowerBound < neutral ? neutral : nil,
                       label: { Text(title) }, onEditingChanged: editingChanged)
            } else {
                Slider(value: binding, in: range, onEditingChanged: editingChanged)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .accessibilityLabel(title)
        .onChange(of: value) { _, _ in if !dragging { position = nil } }
    }

    private func editingChanged(_ editing: Bool) {
        dragging = editing
        onEditing(editing)
        if !editing { position = nil }
    }

    private func reset() {
        position = nil
        onEditing(true)
        onChange(neutral)
        onEditing(false)
    }
}

/// Collapsible inspector section. `number` shows the node order; `isOn`
/// adds a stage switch (bypass) like Lightroom panel switches / Resolve node enable.
struct InspectorSection<Content: View>: View {
    let title: String
    var number: Int?
    var isOn: Binding<Bool>?
    var help: String?
    var onReset: (() -> Void)?
    @ViewBuilder var content: Content
    @AppStorage private var collapsed: Bool

    init(_ title: String, number: Int? = nil, isOn: Binding<Bool>? = nil, help: String? = nil,
         startsCollapsed: Bool = false, onReset: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.number = number; self.isOn = isOn; self.help = help; self.onReset = onReset
        self.content = content()
        _collapsed = AppStorage(wrappedValue: startsCollapsed, "section.collapsed.\(title)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { withAnimation(.snappy(duration: 0.18)) { collapsed.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        if let number {
                            Text("\(number)")
                                .font(.caption2.weight(.bold)).monospacedDigit()
                                .frame(width: 15, height: 15)
                                .background(Circle().fill(isOn?.wrappedValue == false ? Color.secondary.opacity(0.25) : WorkbenchTheme.accent.opacity(0.85)))
                                .foregroundStyle(.black.opacity(0.8))
                        }
                        Text(title).font(.headline)
                            .foregroundStyle(isOn?.wrappedValue == false ? .secondary : .primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help ?? title)
                Spacer(minLength: 4)
                if let onReset {
                    Button(action: onReset) { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("复位\(title)")
                        .accessibilityLabel("复位\(title)")
                }
                if let isOn {
                    Toggle(isOn: isOn) { EmptyView() }
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .help(isOn.wrappedValue ? "关闭此步骤以比较效果（参数保留）" : "开启此步骤")
                        .accessibilityLabel("\(title)开关")
                }
            }
            if !collapsed {
                content
                    .opacity(isOn?.wrappedValue == false ? 0.45 : 1)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { WorkbenchTheme.hairline.frame(height: 1) }
    }
}

struct SubHeading: View {
    let title: String
    var trailing: AnyView?
    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.top, 2)
    }
}

struct IconButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(active ? WorkbenchTheme.accent : .primary)
                .frame(width: 20, height: 20)
        }
        .glassButton(.circle)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct RatingStars: View {
    let rating: Int
    var size: CGFloat = 9
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<rating, id: \.self) { _ in Image(systemName: "star.fill") }
        }
        .font(.system(size: size))
        .foregroundStyle(WorkbenchTheme.accent)
        .accessibilityLabel("\(rating) 星")
    }
}

struct FlagBadge: View {
    let flag: LibraryFlag
    var body: some View {
        switch flag {
        case .pick: Image(systemName: "flag.fill").foregroundStyle(WorkbenchTheme.pick).accessibilityLabel("已选用")
        case .reject: Image(systemName: "xmark.circle.fill").foregroundStyle(WorkbenchTheme.reject).accessibilityLabel("已排除")
        case .none: EmptyView()
        }
    }
}

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar; view.blendingMode = .behindWindow; view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    @ViewBuilder func primaryButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent).tint(WorkbenchTheme.accent)
        } else {
            self.buttonStyle(.borderedProminent).tint(WorkbenchTheme.accent)
        }
    }

    /// Liquid Glass capsule on macOS 26 (adapts to the photo underneath);
    /// a dark material capsule on earlier systems.
    @ViewBuilder func hudBackground() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Color.black.opacity(0.35), in: Capsule())
        }
    }

    /// Secondary actions: Liquid Glass buttons on macOS 26, bordered before.
    @ViewBuilder func glassButton(_ shape: ButtonBorderShape = .capsule) -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass).buttonBorderShape(shape)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(shape)
        }
    }
}

func durationLabel(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        : String(format: "%d:%02d", total / 60, total % 60)
}

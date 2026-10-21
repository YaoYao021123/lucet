import AppKit
import MediaCore
import SwiftUI

/// `@State` is a macro in this SDK and Command Line Tools lack the SwiftUI macro
/// plugin; the alias names the property wrapper directly so it builds without Xcode.
typealias UIState<Value> = SwiftUI.State<Value>

enum WorkbenchTheme {
    /// A calm version of the System Settings accent (half the saturation, a little darker),
    /// read once at launch. Used sparingly: the main action and "this is on" states only —
    /// colorful chrome next to a photo biases how its colors are judged.
    /// For symbols, strokes and tinted text on dark surfaces. A fill that carries white text is `accentFill`.
    static let accent: Color = calmAccent(brightnessScale: 0.8).color
    /// The same accent, darkened until white text (`onAccent`) on it reaches 4.5:1: prominent buttons,
    /// selected export segments, the tick on a chosen photo. The two always travel as a pair.
    static let accentFill: Color = {
        var scale = 0.8
        while scale > 0.25, contrastWithWhite(calmAccent(brightnessScale: scale)) < 4.6 { scale -= 0.01 }
        return calmAccent(brightnessScale: scale).color
    }()
    static let onAccent = Color.white

    private typealias RGB = (red: Double, green: Double, blue: Double)

    private static func calmAccent(brightnessScale: Double) -> (color: Color, rgb: RGB) {
        let system = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        let muted = NSColor(hue: system.hueComponent, saturation: system.saturationComponent * 0.5,
                            brightness: system.brightnessComponent * brightnessScale, alpha: 1)
        let rgb = (red: Double(muted.redComponent), green: Double(muted.greenComponent), blue: Double(muted.blueComponent))
        return (Color(red: rgb.red, green: rgb.green, blue: rgb.blue), rgb)
    }

    /// WCAG contrast ratio of white against the color.
    private static func contrastWithWhite(_ accent: (color: Color, rgb: RGB)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(accent.rgb.red) + 0.7152 * linear(accent.rgb.green) + 0.0722 * linear(accent.rgb.blue)
        return 1.05 / (luminance + 0.05)
    }

    /// Text on the dark panels. The system's `.secondary` / `.tertiary` fade to about 3:1 / 2.3:1 on the
    /// tinted glass, so anything meant to be read (names, units, captions, explanations) uses this instead:
    /// white at 70% stays above 4.5:1 on every panel tint measured. Hierarchy comes from size and weight.
    static let textSecondary = Color.white.opacity(0.7)
    /// Neutral tints for everything that doesn't need color. `neutralTint` is the window's
    /// default tint, so text buttons, switches and checkboxes stay gray unless a view opts in.
    static let control = Color(white: 0.72)
    static let neutralTint = Color(white: 0.84)
    static let selection = Color.white.opacity(0.12)
    static let selectionStroke = Color.white.opacity(0.4)
    /// Ratings stay neutral (Lightroom-style) so they never compete with the accent.
    static let star = Color(white: 0.9)
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
    var labelWidth: CGFloat = 56
    /// Hovering the name shows where this control acts in the photo.
    var influence: InfluenceKind?
    let onChange: (Double) -> Void
    var onEditing: (Bool) -> Void = { _ in }
    var onHover: (InfluenceKind?) -> Void = { _ in }
    /// Hovering anywhere on the row or dragging: the histogram shows this control's zones.
    var onFocus: (Bool) -> Void = { _ in }
    /// "What does this do?" in the row's menu: a demo on this photo (nil: none, or switched off).
    var learnMore: (@MainActor () -> Void)?
    /// Softly lit for a moment after a lesson about it.
    var spotlit = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.value == rhs.value && lhs.range == rhs.range && lhs.step == rhs.step
            && lhs.decimals == rhs.decimals && lhs.suffix == rhs.suffix && lhs.neutral == rhs.neutral
            && lhs.influence == rhs.influence && lhs.spotlit == rhs.spotlit && (lhs.learnMore == nil) == (rhs.learnMore == nil)
    }

    @UIState private var position: Double?
    @UIState private var dragging = false
    @Environment(\.isEnabled) private var enabled

    private func clamp(_ next: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, (next / step).rounded() * step))
    }

    var body: some View {
        HStack(spacing: 8) {
            // Both states stay readable (an untouched, enabled name is not a disabled one); a changed
            // parameter is a notch brighter and heavier.
            Text(title)
                .fontWeight(value == neutral ? .regular : .medium)
                .foregroundStyle(value == neutral ? WorkbenchTheme.textSecondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: .label(labelWidth), alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { reset() }
                .onHover { inside in if influence != nil { onHover(inside ? influence : nil) } }
                .help((help.map { $0 + "\n" } ?? "") + (influence != nil ? L("悬停名称可在画面上查看影响范围；") : "") + L("双击名称恢复默认"))
            slider
            HStack(spacing: 2) {
                TextField("", value: Binding(get: { value }, set: { next in if next.isFinite { onChange(clamp(next)) } }),
                          format: .number.precision(.fractionLength(decimals)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("\(title)数值")
                Text(suffix).font(.caption).foregroundStyle(WorkbenchTheme.textSecondary).frame(width: 13, alignment: .leading)
            }
            .frame(width: 48)
        }
        .font(.subheadline)
        .frame(height: 18)
        .contentShape(Rectangle())
        .onHover { inside in if !dragging { onFocus(inside) } }
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(spotlit ? 0.1 : 0)).padding(.horizontal, -4).padding(.vertical, -2))
        .animation(.easeOut(duration: 0.8), value: spotlit)
        .contextMenu {
            Button("恢复默认值") { reset() }
            if let learnMore { Button(L("「\(title)」是做什么的？")) { learnMore() } }
        }
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
        .controlSize(.mini)
        .tint(WorkbenchTheme.control)
        .accessibilityLabel(title)
        .onChange(of: value) { _, _ in if !dragging { position = nil } }
    }

    private func editingChanged(_ editing: Bool) {
        dragging = editing
        onFocus(editing)
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
    /// A demo of this section on the photo, offered next to the title while the pointer is over it.
    var lesson: (@MainActor () -> Void)?
    @ViewBuilder var content: Content
    @AppStorage private var collapsed: Bool
    @UIState private var hovering = false

    init(_ title: String, number: Int? = nil, isOn: Binding<Bool>? = nil, help: String? = nil,
         startsCollapsed: Bool = false, onReset: (() -> Void)? = nil, lesson: (@MainActor () -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.number = number; self.isOn = isOn; self.help = help; self.onReset = onReset; self.lesson = lesson
        self.content = content()
        _collapsed = AppStorage(wrappedValue: startsCollapsed, "section.collapsed.\(title)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(isOn?.wrappedValue == false ? Color.secondary.opacity(0.15) : Color.white.opacity(0.2)))
                                .foregroundStyle(.white)
                        }
                        Text(title).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isOn?.wrappedValue == false ? .secondary : .primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help ?? title)
                if let lesson {
                    // Quiet until wanted: it shows while the pointer is on the header and stays reachable by keyboard.
                    Button(action: lesson) { Image(systemName: "play.circle").font(.caption) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                        .opacity(hovering ? 1 : 0)
                        .help(L("用这张照片看一段演示"))
                        .accessibilityLabel(L("\(title)演示"))
                }
                Spacer(minLength: 4)
                if let onReset {
                    Button(action: onReset) { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("复位\(title)")
                        .accessibilityLabel("复位\(title)")
                }
                if let isOn {
                    // Photoshop-style visibility eye instead of a row of colored switches.
                    Button { isOn.wrappedValue.toggle() } label: {
                        Image(systemName: isOn.wrappedValue ? "eye" : "eye.slash")
                            .foregroundStyle(isOn.wrappedValue ? Color.primary : Color.secondary)
                            .frame(width: 20, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(isOn.wrappedValue ? L("隐藏此步骤的效果以比较（参数保留）") : L("显示此步骤的效果"))
                    .accessibilityLabel("\(title)：\(isOn.wrappedValue ? String(localized: "state.on", defaultValue: "开启") : String(localized: "state.off", defaultValue: "关闭"))") // loc:ignore (defaultValue)
                }
            }
            if !collapsed {
                content
                    .opacity(isOn?.wrappedValue == false ? 0.45 : 1)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { WorkbenchTheme.hairline.frame(height: 1) }
        .onHover { hovering = $0 }
    }
}

struct IconButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void
    var body: some View {
        // No foreground of our own: the glass style picks the symbol colour that suits its surface (a fixed
        // `.primary` is white in the dark scheme, on glass that can be pale). The on state is the prominent
        // style, whose accent fill and white symbol are one pair.
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 20, height: 20)
        }
        Group {
            if active { button.primaryButton().buttonBorderShape(.circle) } else { button.glassButton(.circle) }
        }
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
        .foregroundStyle(WorkbenchTheme.star)
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
            self.buttonStyle(.glassProminent).tint(WorkbenchTheme.accentFill)
        } else {
            self.buttonStyle(.borderedProminent).tint(WorkbenchTheme.accentFill)
        }
    }

    /// A sheet's Return button: the system fills it with the tint and draws its own white label, so the
    /// tint is the fill white text reads on (the sheet itself keeps the lighter `accent`).
    func defaultActionButton() -> some View {
        self.keyboardShortcut(.defaultAction).tint(WorkbenchTheme.accentFill)
    }

    /// Native segmented picker whose selected segment is filled with the accent. The fill is dark enough
    /// for the white label the system draws on it; the rest of the sheet keeps the lighter `accent` tint.
    func accentSegments() -> some View {
        self.pickerStyle(.segmented).tint(WorkbenchTheme.accentFill)
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

extension CGFloat {
    /// Label columns are sized for 2–4 Chinese characters; English words need more room.
    static func label(_ chinese: CGFloat) -> CGFloat {
        AppLanguage.current == .chinese ? chinese : (chinese * 1.65).rounded()
    }
}

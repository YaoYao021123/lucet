import AppKit
import SwiftUI

typealias UIState<Value> = SwiftUI.State<Value>

enum WorkbenchTheme {
    static let accent = Color(red: 0.78, green: 0.70, blue: 0.48)
    static let panel = Color(white: 0.105)
    static let timeline = Color(white: 0.075)
    static let hairline = Color.white.opacity(0.075)
}

struct IconButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .regular))
                .foregroundStyle(active ? WorkbenchTheme.accent : .primary)
                .frame(width: 22, height: 22)
        }.workstationButton(shape: .circle)
            .help(title).accessibilityLabel(title)
    }
}

struct InfoButton: View {
    let text: String
    @UIState private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 28, height: 28)
        }.buttonStyle(.plain).help(text).accessibilityLabel("说明")
            .popover(isPresented: $showing) {
                Text(text).font(.system(size: 12)).lineSpacing(4).padding(18).frame(width: 290)
            }
    }
}

struct PanelHeading: View {
    let title: String
    var info: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            if let info { InfoButton(text: info) }
        }.frame(height: 28)
    }
}

/// A quiet parameter control with a wide hit target, typed values, and AX adjustment.
struct ParameterControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var suffix = ""
    var decimals = 0
    var resetValue: Double = 0
    var onEditingChanged: (Bool) -> Void = { _ in }
    var info: String? = nil
    private var bounded: Binding<Double> {
        Binding(get: { value }, set: { next in
            guard next.isFinite else { return }
            value = min(range.upperBound, max(range.lowerBound, (next / step).rounded() * step))
        })
    }
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(title).foregroundStyle(.secondary)
                if let info { InfoButton(text: info) }
                Spacer()
                TextField(title, value: bounded, format: .number.precision(.fractionLength(decimals)))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .frame(width: 58).monospacedDigit().accessibilityLabel("\(title)数值")
                Text(suffix).foregroundStyle(.secondary)
            }.font(.system(size: 13)).frame(height: 26)
            NativeParameterSlider(value: bounded, range: range, step: step, resetValue: resetValue, title: title, onEditingChanged: onEditingChanged)
        }
    }
}

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar; view.blendingMode = .withinWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}

extension View {
    @ViewBuilder func workstationPrimaryButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent).controlSize(.regular)
                .buttonBorderShape(.capsule).tint(WorkbenchTheme.accent).font(.system(size: 13))
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.regular)
                .buttonBorderShape(.capsule).tint(WorkbenchTheme.accent).font(.system(size: 13))
        }
    }

    @ViewBuilder func workstationButton(shape: ButtonBorderShape = .capsule) -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass).controlSize(.regular)
                .buttonBorderShape(shape).tint(nil as Color?)
                .font(.system(size: 13)).foregroundStyle(.primary)
        } else {
            self.buttonStyle(.bordered).controlSize(.regular)
                .buttonBorderShape(shape).tint(nil as Color?)
                .font(.system(size: 13)).foregroundStyle(.primary)
        }
    }

    @ViewBuilder func workstationGlass() -> some View {
        if #available(macOS 26, *) { self.glassEffect(.regular, in: Capsule()) }
        else { self.background(.regularMaterial, in: Capsule()) }
    }
}

func timeLabel(_ seconds: Double) -> String {
    let centiseconds = Int(max(0, seconds.isFinite ? seconds : 0) * 100)
    return String(format: "%02d:%02d.%02d", centiseconds / 6000, (centiseconds / 100) % 60, centiseconds % 100)
}

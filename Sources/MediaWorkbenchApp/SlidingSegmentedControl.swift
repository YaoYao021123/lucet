import SwiftUI

/// Native material with an app-specific, continuously draggable selection.
struct SlidingSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var accessibilityTitle = "检查器"
    @GestureState private var dragX: CGFloat?
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(max(1, options.count))
            let index = options.firstIndex(of: selection) ?? 0
            let x = dragX.map { min(max(0, $0 - width / 2), geometry.size.width - width) }
                ?? CGFloat(index) * width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06))
                selectionMaterial
                    .frame(width: max(0, width - 8), height: 28)
                    .offset(x: x + 4)
                    .animation(reduceMotion || dragX != nil ? nil : .smooth(duration: 0.24), value: x)
                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        Button { selection = option } label: {
                            Text(title(option)).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(selection == option ? .primary : .secondary)
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title(option))\(accessibilityTitle)")
                        .accessibilityAddTraits(selection == option ? [.isSelected] : [])
                    }
                }
            }
            .contentShape(Capsule())
            .highPriorityGesture(DragGesture(minimumDistance: 4)
                .updating($dragX) { value, state, _ in
                    if enabled { state = value.location.x }
                }
                .onEnded { value in
                    guard enabled, !options.isEmpty, width > 0 else { return }
                    let index = min(options.count - 1, max(0, Int(floor(value.location.x / width))))
                    selection = options[index]
                })
        }
        .frame(height: 36)
        .opacity(enabled ? 1 : 0.45)
    }

    @ViewBuilder private var selectionMaterial: some View {
        if #available(macOS 26, *), !reduceTransparency {
            Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(Color.primary.opacity(0.14))
        }
    }
}

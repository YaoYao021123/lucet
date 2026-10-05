import SwiftUI

/// Keep the thumb's continuous value separate from quantized media parameters.
struct NativeParameterSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let resetValue: Double
    let title: String
    let onEditingChanged: (Bool) -> Void
    @UIState private var position: Double
    @UIState private var dragging = false
    @UIState private var pendingUpdate: Task<Void, Never>?
    @FocusState private var keyboardFocus: Bool

    init(value: Binding<Double>, range: ClosedRange<Double>, step: Double,
         resetValue: Double, title: String, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        _value = value
        self.onEditingChanged = onEditingChanged
        self.range = range; self.step = step; self.resetValue = resetValue; self.title = title
        _position = UIState(initialValue: value.wrappedValue)
    }

    var body: some View {
        systemSlider
            .controlSize(.regular)
            .accessibilityLabel(title)
            .focusable()
            .focused($keyboardFocus)
            .onChange(of: position) { _, next in
                if dragging { scheduleUpdate() }
                else { commit(next) }
            }
            .onChange(of: value) { _, next in
                // Incoming rounded values must not pull back a moving thumb.
                if !dragging, position != next { position = next }
            }
            .onKeyPress(.leftArrow) { increment(-step); return .handled }
            .onKeyPress(.downArrow) { increment(-step); return .handled }
            .onKeyPress(.rightArrow) { increment(step); return .handled }
            .onKeyPress(.upArrow) { increment(step); return .handled }
            .contextMenu { Button("恢复默认值") { position = resetValue; commit(resetValue) } }
            .help("拖动或用方向键调整，右键恢复默认值；也可直接输入数值。")
            .onDisappear { pendingUpdate?.cancel(); pendingUpdate = nil; if dragging { commit(position); onEditingChanged(false) } }
    }

    @ViewBuilder private var systemSlider: some View {
        if #available(macOS 26, *) {
            Slider(value: $position, in: range,
                   neutralValue: range.lowerBound < 0 ? resetValue : nil,
                   label: { Text(title) }, onEditingChanged: editingChanged).labelsHidden()
        } else {
            Slider(value: $position, in: range, onEditingChanged: editingChanged)
        }
    }

    private func editingChanged(_ editing: Bool) {
        dragging = editing
        if editing { keyboardFocus = true; onEditingChanged(true) }
        if !editing {
            pendingUpdate?.cancel(); pendingUpdate = nil
            commit(position)
            onEditingChanged(false)
        }
    }

    private func scheduleUpdate() {
        guard pendingUpdate == nil else { return }
        pendingUpdate = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(33)) }
            catch { return }
            guard !Task.isCancelled else { return }
            // Read the newest local position instead of retaining every event.
            commit(position)
            pendingUpdate = nil
        }
    }

    private func commit(_ next: Double) {
        guard next.isFinite else { return }
        let rounded = (next / step).rounded() * step
        let result = min(range.upperBound, max(range.lowerBound, rounded))
        if value != result { value = result }
    }

    private func increment(_ amount: Double) {
        position = min(range.upperBound, max(range.lowerBound, position + amount))
        commit(position)
    }
}

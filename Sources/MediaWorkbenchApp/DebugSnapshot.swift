import AppKit

/// Developer-only layout check. Launch with
/// `GUANGJI_SNAPSHOT_DIR=/tmp/shots GUANGJI_SNAPSHOT_STEPS="open:/a.jpg;wait:2;shot:edit;quit"`
/// to save PNGs of the app's own window without screen-recording permission.
/// Metal and video layers are not captured by AppKit's view cache.
@MainActor
enum DebugSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["GUANGJI_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func runIfRequested(_ perform: @escaping @MainActor (String, String) -> Void) {
        guard directory != nil, let script = ProcessInfo.processInfo.environment["GUANGJI_SNAPSHOT_STEPS"] else { return }
        let steps = script.split(separator: ";").map { step -> (String, String) in
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            for (command, argument) in steps {
                switch command {
                case "wait": try? await Task.sleep(for: .seconds(Double(argument) ?? 1))
                case "shot": capture(named: argument)
                case "size":
                    let values = argument.split(separator: "x").compactMap { Double($0) }
                    if values.count == 2, let window = workbenchWindow {
                        window.setContentSize(NSSize(width: values[0], height: values[1]))
                    }
                case "quit": NSApp.terminate(nil)
                default: perform(command, argument)
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    static var workbenchWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("workbench") == true && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
    }

    static func capture(named name: String) {
        guard let directory else { return }
        let window = NSApp.keyWindow ?? workbenchWindow
        guard let window, let content = window.contentView else { return }
        let view = content.superview ?? content
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

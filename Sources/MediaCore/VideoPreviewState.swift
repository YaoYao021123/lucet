import Foundation

/// Filter callbacks run outside the main actor. Publish one complete parameter
/// snapshot so the player can keep its decoder and composition while editing.
public final class VideoPreviewState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MediaEdits
    public let maximumDimension: Double

    public init(edits: MediaEdits, maximumDimension: Double = 1600) {
        value = edits
        self.maximumDimension = maximumDimension.isFinite ? max(2, maximumDimension) : 1600
    }
    public func update(_ edits: MediaEdits) {
        lock.lock(); defer { lock.unlock() }
        value = edits
    }
    public func snapshot() -> MediaEdits {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

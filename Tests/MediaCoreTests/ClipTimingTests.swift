import Foundation
import Testing
@testable import MediaCore

struct ClipTimingTests {
    @Test func movingSelectionPreservesLengthCoverAndSpeedAtBothEdges() {
        let clip = ClipSettings(start: 4, end: 10, cover: 7, speed: 2)
        for delta in [-100.0, -2, 0, 3, 100] {
            let moved = clip.shifted(by: delta, duration: 20)
            #expect(moved.sourceDuration == 6)
            #expect(moved.cover - moved.start == 3)
            #expect(moved.start >= 0 && moved.end <= 20)
            #expect(moved.outputDuration == 3)
            #expect(moved.outputCover == 1.5)
        }
        #expect(clip.shifted(by: -100, duration: 20).start == 0)
        #expect(clip.shifted(by: 100, duration: 20).end == 20)
    }
    @Test func liveValidationUsesOutputTimeAndRejectsInvalidSpeeds() throws {
        try ClipSettings(start: 2, end: 8, cover: 5, speed: 2).validate(duration: 10, live: true)
        for speed in [0.0, -1, Double.nan, .infinity, 4.1] {
            #expect(throws: VideoWorkError.self) {
                try ClipSettings(start: 2, end: 8, cover: 5, speed: speed).validate(duration: 10, live: true)
            }
        }
        #expect(throws: VideoWorkError.self) {
            try ClipSettings(start: 2, end: 8, cover: 5, speed: 1).validate(duration: 10, live: true)
        }
    }
}

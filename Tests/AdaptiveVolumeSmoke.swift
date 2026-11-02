import Foundation

@main
enum AdaptiveVolumeSmoke {
    static func main() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func reading(_ dB: Double, minutesAgo: Double = 0) -> AdaptiveVolume.Reading {
            AdaptiveVolume.Reading(noiseDB: dB, takenAt: now.addingTimeInterval(-minutesAgo * 60))
        }
        func close(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.0001 }

        // No reading, or a quiet room: exactly the person's setting.
        precondition(close(AdaptiveVolume.volume(base: 0.6, reading: nil, now: now), 0.6))
        precondition(close(AdaptiveVolume.volume(base: 0.6, reading: reading(-70), now: now), 0.6))

        // Loud room: full volume. Halfway: halfway between setting and full.
        precondition(close(AdaptiveVolume.volume(base: 0.6, reading: reading(-20), now: now), 1.0))
        precondition(close(AdaptiveVolume.volume(base: 0.6, reading: reading(-40), now: now), 0.8))

        // Never quieter than the setting; never above full.
        for dB in stride(from: -90.0, through: 0, by: 5) {
            let v = AdaptiveVolume.volume(base: 0.5, reading: reading(dB), now: now)
            precondition(v >= 0.5 && v <= 1.0, "out of range at \(dB): \(v)")
        }
        precondition(close(AdaptiveVolume.volume(base: 1.4, reading: nil, now: now), 1.0))

        // A stale reading is ignored.
        precondition(close(AdaptiveVolume.volume(base: 0.6, reading: reading(-20, minutesAgo: 11), now: now), 0.6))
        precondition(close(AdaptiveVolume.volume(base: 0.6, reading: reading(-20, minutesAgo: 9), now: now), 1.0))

        // Room level is the quiet end of the frames, not the talking.
        let frames = [Double](repeating: 0.003, count: 40) + [Double](repeating: 0.3, count: 60)
        let room = AdaptiveVolume.roomNoiseDB(frameRMS: frames)!
        precondition(abs(room - RecordingQuality.dB(0.003)) < 0.01, "room should ignore speech, got \(room)")
        precondition(AdaptiveVolume.roomNoiseDB(frameRMS: [0.1, 0.1]) == nil, "too few frames to judge")
        precondition(AdaptiveVolume.describe(-60) == "Quiet" && AdaptiveVolume.describe(-30) == "Loud")

        print("adaptive-volume: all checks passed")
    }
}

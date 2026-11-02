import Foundation

/// Raises speech volume in a noisy room, from an on-device reading of the room.
///
/// The person's own volume setting is the floor: a quiet room never makes
/// EchoVoice quieter than they chose, because a voice that unexpectedly drops is
/// worse than one that stays the same. A loud room raises it toward full, and
/// the phone's system volume is still the ceiling — this cannot be louder than
/// the person has allowed the phone to be.
///
/// Room readings go stale. A reading taken in a loud kitchen must not keep
/// boosting the voice an hour later in a bedroom, so readings older than
/// `maxReadingAge` are ignored.
enum AdaptiveVolume {
    /// At or below this room level, speech stays at the person's setting.
    static let quietRoomDB = -55.0
    /// At or above this room level, speech goes to full volume.
    static let loudRoomDB = -25.0
    /// A room reading older than this is ignored.
    static let maxReadingAge: TimeInterval = 10 * 60

    struct Reading: Equatable, Sendable {
        var noiseDB: Double
        var takenAt: Date
    }

    static func volume(base: Float, reading: Reading?, now: Date = .now) -> Float {
        let base = min(max(base, 0), 1)
        guard let reading, now.timeIntervalSince(reading.takenAt) <= maxReadingAge else { return base }
        let t = (reading.noiseDB - quietRoomDB) / (loudRoomDB - quietRoomDB)
        let clamped = Float(min(max(t, 0), 1))
        return base + (1 - base) * clamped
    }

    /// The room's level from a run of frame levels (RMS, linear).
    ///
    /// Uses the 20th percentile, not the average: in a conversation the loudest
    /// frames are people talking, and the room is what is left between words.
    static func roomNoiseDB(frameRMS: [Double]) -> Double? {
        guard frameRMS.count >= 5 else { return nil }
        let sorted = frameRMS.sorted()
        return RecordingQuality.dB(sorted[Int(Double(sorted.count - 1) * 0.2)])
    }

    /// Plain-language label for a room level, for the settings readout.
    static func describe(_ noiseDB: Double) -> String {
        switch noiseDB {
        case ..<(-50): return String(localized: "Quiet")
        case ..<(-38): return String(localized: "Moderate")
        default: return String(localized: "Loud")
        }
    }
}

import Foundation

/// Synthetic recordings with one known flaw each. A voiced stretch is a 180 Hz
/// tone with a syllable-rate envelope; "silence" is a faint noise floor, the
/// way a real phone microphone never reads exactly zero.
@main
enum RecordingQualitySmoke {
    static let rate = 16_000.0

    static func noise(_ seconds: Double, amplitude: Float, seed: inout UInt64) -> [Float] {
        (0..<Int(seconds * rate)).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float(seed >> 40) / Float(1 << 24)   // 0..<1
            return (unit * 2 - 1) * amplitude
        }
    }

    static func voice(_ seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(seconds * rate)).map { i in
            let t = Double(i) / rate
            let envelope = 0.6 + 0.4 * sin(2 * .pi * 4 * t)
            return Float(sin(2 * .pi * 180 * t) * envelope) * amplitude
        }
    }

    static func mix(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map(+) }

    static func main() {
        var seed: UInt64 = 7

        // Clean: quiet lead-in, speech, quiet tail.
        let clean = noise(0.3, amplitude: 0.001, seed: &seed) + voice(1.0, amplitude: 0.3) + noise(0.3, amplitude: 0.001, seed: &seed)
        let cleanReport = RecordingQuality.analyze(samples: clean, sampleRate: rate)
        precondition(cleanReport.isClear, "clean recording flagged: \(cleanReport.issues)")
        precondition(cleanReport.snrDB > 30, "clean SNR should be large, got \(cleanReport.snrDB)")
        precondition(cleanReport.measuredNoise)

        // Clipped: driven past full scale.
        let hot = voice(1.0, amplitude: 1.6).map { min(max($0, -1), 1) }
        let clipped = noise(0.3, amplitude: 0.001, seed: &seed) + hot + noise(0.3, amplitude: 0.001, seed: &seed)
        let clippedReport = RecordingQuality.analyze(samples: clipped, sampleRate: rate)
        precondition(clippedReport.issues.contains(.clipped), "clipping missed: \(clippedReport.issues)")

        // Too quiet, but still clearly speech.
        let quiet = noise(0.3, amplitude: 0.0001, seed: &seed) + voice(1.0, amplitude: 0.012) + noise(0.3, amplitude: 0.0001, seed: &seed)
        let quietReport = RecordingQuality.analyze(samples: quiet, sampleRate: rate)
        precondition(quietReport.issues == [.tooQuiet], "quiet: \(quietReport.issues) at \(quietReport.speechLevelDB) dB")

        // Nothing at all.
        let silent = noise(1.5, amplitude: 0.0005, seed: &seed)
        precondition(RecordingQuality.analyze(samples: silent, sampleRate: rate).issues == [.noSpeech])
        precondition(RecordingQuality.analyze(samples: [], sampleRate: rate).issues == [.noSpeech])

        // Noisy room: noise under the whole recording, clean timing.
        let speechTrack = [Float](repeating: 0, count: Int(0.3 * rate)) + voice(1.0, amplitude: 0.3) + [Float](repeating: 0, count: Int(0.3 * rate))
        let noisy = mix(speechTrack, noise(1.6, amplitude: 0.12, seed: &seed))
        let noisyReport = RecordingQuality.analyze(samples: noisy, sampleRate: rate)
        precondition(noisyReport.issues.contains(.noisy), "noise missed: \(noisyReport.issues), SNR \(noisyReport.snrDB)")
        precondition(!noisyReport.issues.contains(.cutOffStart) && !noisyReport.issues.contains(.cutOffEnd),
                     "a noisy room is not a cut-off recording: \(noisyReport.issues)")

        // Stop pressed mid-word: silence before, none after. 1.0625 s ends on a
        // syllable peak of the 4 Hz envelope, i.e. while still talking.
        let cutEnd = noise(0.3, amplitude: 0.001, seed: &seed) + voice(1.0625, amplitude: 0.3)
        let cutEndReport = RecordingQuality.analyze(samples: cutEnd, sampleRate: rate)
        precondition(cutEndReport.issues == [.cutOffEnd], "cut end: \(cutEndReport.issues)")

        // Speech wall to wall: both ends cut, and the room must not be blamed.
        let wall = voice(1.0625, amplitude: 0.3)
        let wallReport = RecordingQuality.analyze(samples: wall, sampleRate: rate)
        precondition(wallReport.issues.contains(.cutOffStart) && wallReport.issues.contains(.cutOffEnd))
        precondition(!wallReport.issues.contains(.noisy) && !wallReport.measuredNoise,
                     "noise can't be measured without a quiet stretch: \(wallReport.issues)")

        // Any sample rate the microphone happens to use.
        let cd = (0..<Int(1.6 * 44_100)).map { i -> Float in
            let t = Double(i) / 44_100
            return (t > 0.3 && t < 1.3) ? Float(sin(2 * .pi * 180 * t)) * 0.3 : 0.0005
        }
        precondition(RecordingQuality.analyze(samples: cd, sampleRate: 44_100).isClear, "44.1 kHz recording should be clear")

        print("recording-quality: all checks passed")
    }
}

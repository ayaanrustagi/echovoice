import Foundation

/// Tests that the live waveform shows the analysis that is actually saved.
///
/// The waveform's whole claim is that the voiced/unvoiced shading a person
/// watches *is* the split the pause ratio comes from. If the streaming path
/// framed the audio differently, or settled on a different silence threshold,
/// the display would be a decorative level meter wearing the language of
/// measurement — which is worse than not showing one.
///
/// So the checks are about agreement with `SpeechAnalysis`, not about looks.
@main
struct LiveTraceSmoke {
    private static let sampleRate = 16_000.0

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(sampleRate * seconds))
    }

    private static func tone(_ seconds: Double, frequency: Double = 180, amplitude: Double = 0.3) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { index in
            Float(amplitude * sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
    }

    @MainActor
    static func main() {
        checkFramingMatchesBatchAnalysis()
        checkChunkBoundariesDoNotChangeResult()
        checkPauseRatioTracksBatchAnalysis()
        checkPitchIsInRange()
        checkResetClearsEverything()
        print("Live trace smoke tests passed")
    }

    /// Same frame and hop geometry as the one-shot analyzer.
    @MainActor
    private static func checkFramingMatchesBatchAnalysis() {
        let samples = tone(2)
        let trace = LiveSpeechTrace()
        trace.reset(sampleRate: sampleRate)
        trace.append(samples)

        let frameSize = SpeechAnalysis.frameSize(at: sampleRate)
        let hopSize = SpeechAnalysis.hopSize(at: sampleRate)
        let expectedFrames = (samples.count - frameSize) / hopSize + 1

        precondition(frameSize == 400, "frame size drifted from 25 ms at 16 kHz")
        precondition(hopSize == 160, "hop size drifted from 10 ms at 16 kHz")
        precondition(
            trace.totalFrames == expectedFrames,
            "streamed \(trace.totalFrames) frames where the batch analyzer would see \(expectedFrames)"
        )
    }

    /// Audio arrives in whatever sizes the hardware hands over, and those buffer
    /// boundaries never align with frame boundaries. Splitting the same audio
    /// differently must not change a single frame.
    @MainActor
    private static func checkChunkBoundariesDoNotChangeResult() {
        let samples = silence(0.3) + tone(1.2) + silence(0.3)

        let whole = LiveSpeechTrace()
        whole.reset(sampleRate: sampleRate)
        whole.append(samples)

        let chunked = LiveSpeechTrace()
        chunked.reset(sampleRate: sampleRate)
        // Deliberately awkward sizes: coprime with both frame and hop.
        var offset = 0
        for size in [1023, 337, 4096, 71] .cycled(upTo: samples.count) {
            let end = min(offset + size, samples.count)
            if offset >= end { break }
            chunked.append(Array(samples[offset..<end]))
            offset = end
        }
        if offset < samples.count {
            chunked.append(Array(samples[offset...]))
        }

        precondition(
            whole.totalFrames == chunked.totalFrames,
            "chunking changed the frame count: \(whole.totalFrames) vs \(chunked.totalFrames)"
        )
        precondition(
            whole.frames.map(\.voiced) == chunked.frames.map(\.voiced),
            "chunking changed which frames counted as voiced"
        )
    }

    /// The number under the waveform must land near the one the check-in saves.
    @MainActor
    private static func checkPauseRatioTracksBatchAnalysis() {
        // Kept inside the display window so the live figure covers the same span
        // the batch analyzer does.
        let samples = tone(0.8) + silence(0.5) + tone(0.8)

        let trace = LiveSpeechTrace()
        trace.reset(sampleRate: sampleRate)
        trace.append(samples)

        let batch = SpeechAnalysis.analyze(samples: samples, sampleRate: sampleRate, wordCount: 5)

        precondition(trace.hasSignal, "a clear two-second utterance registered as no signal")
        precondition(
            abs(trace.windowPauseRatio - batch.pauseRatio) < 0.06,
            "live pause ratio \(trace.windowPauseRatio) disagreed with saved \(batch.pauseRatio)"
        )
    }

    /// A displayed pitch track outside the estimator's own range would be
    /// drawing something the analyzer would have discarded.
    @MainActor
    private static func checkPitchIsInRange() {
        let trace = LiveSpeechTrace()
        trace.reset(sampleRate: sampleRate)
        trace.append(tone(1.5, frequency: 180))

        let pitches = trace.frames.compactMap(\.f0)
        precondition(!pitches.isEmpty, "no pitch was estimated from a steady 180 Hz tone")
        for pitch in pitches {
            precondition(
                pitch >= SpeechAnalysis.minF0Hz && pitch <= SpeechAnalysis.maxF0Hz,
                "estimated \(pitch) Hz, outside the analyzer's accepted range"
            )
        }
        // Decimation means most frames carry no estimate; that is intended, and
        // the drawing code must keep coping with the gaps.
        precondition(pitches.count < trace.totalFrames, "pitch was computed on every frame")
    }

    @MainActor
    private static func checkResetClearsEverything() {
        let trace = LiveSpeechTrace()
        trace.reset(sampleRate: sampleRate)
        trace.append(tone(1))
        precondition(trace.totalFrames > 0, "nothing was captured to reset")

        trace.reset(sampleRate: sampleRate)
        precondition(trace.frames.isEmpty, "frames survived a reset into the next reading")
        precondition(trace.totalFrames == 0, "frame count survived a reset")
        precondition(trace.peakEnergy == 0, "the previous reading's peak carried over")
        precondition(!trace.hasSignal, "a reset trace still reported signal")
    }
}

private extension Array where Element == Int {
    /// Repeat this list of chunk sizes until they cover `total` samples.
    func cycled(upTo total: Int) -> [Int] {
        var sizes: [Int] = []
        var covered = 0
        var index = 0
        while covered < total {
            let size = self[index % count]
            sizes.append(size)
            covered += size
            index += 1
        }
        return sizes
    }
}

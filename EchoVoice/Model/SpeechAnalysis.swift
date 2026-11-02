import Foundation

/// Speech acoustic feature extraction — runs entirely on-device on a recorded
/// reference sentence. No server, no ML library, no network.
///
/// Ported verbatim from the EchoVoice web build's `audioAnalysis.ts` so the two
/// implementations produce the same numbers. Pipeline: frame into 25ms windows
/// (10ms hop) → per-frame RMS energy → adaptive silence threshold splits
/// voiced/unvoiced → pause ratio & speaking rate fall out of that split →
/// per-voiced-frame pitch via autocorrelation → pitch mean/stability. Speaking
/// rate uses the full utterance (including internal pauses); articulation rate
/// uses voiced time only. Leading and trailing silence are trimmed from both.
///
/// These are textbook DSP techniques (short-time energy, adaptive thresholding,
/// autocorrelation pitch detection), chosen over a packaged model because every
/// number stays explainable — it traces back to a specific measurement on the
/// waveform. On iOS the input samples come from AVAudioEngine captured at 16kHz,
/// so no resampling step is needed here.
struct SpeechMetrics: Equatable, Sendable {
    var wpm: Double
    var pauseRatio: Double
    var pitchMean: Double
    var pitchStability: Double
    var articulationRate: Double
    var durationSec: Double
}

enum SpeechAnalysis {
    static let frameMS = 25.0
    static let hopMS = 10.0
    static let targetSampleRate = 16_000.0
    static let minF0Hz = 60.0
    static let maxF0Hz = 400.0
    static let silenceThresholdRatio = 0.08 // fraction of peak frame energy

    /// Extract speech metrics from mono PCM samples (values in roughly -1...1).
    static func analyze(samples: [Float], sampleRate: Double, wordCount: Int) -> SpeechMetrics {
        let durationSec = sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        let frameSize = Int((sampleRate * frameMS) / 1000)
        let hopSize = Int((sampleRate * hopMS) / 1000)

        guard frameSize > 0, hopSize > 0, samples.count >= frameSize else {
            return SpeechMetrics(wpm: 0, pauseRatio: 1, pitchMean: 0,
                                 pitchStability: 0, articulationRate: 0, durationSec: durationSec)
        }

        // Frame boundaries (start indices); each frame is samples[start ..< start+frameSize].
        var frameStarts: [Int] = []
        var start = 0
        while start + frameSize <= samples.count {
            frameStarts.append(start)
            start += hopSize
        }

        let energies = frameStarts.map { s in rms(samples, s, frameSize) }
        let peakEnergy = energies.max() ?? 0
        let silenceThreshold = peakEnergy * silenceThresholdRatio
        let voiced = energies.map { $0 > silenceThreshold }

        guard let firstVoiced = voiced.firstIndex(of: true),
              let lastVoiced = voiced.lastIndex(of: true) else {
            return SpeechMetrics(wpm: 0, pauseRatio: 1, pitchMean: 0,
                                 pitchStability: 0, articulationRate: 0, durationSec: durationSec)
        }

        let activeRange = firstVoiced...lastVoiced
        let voicedCount = activeRange.reduce(0) { $0 + (voiced[$1] ? 1 : 0) }
        let activeFrameCount = activeRange.count
        let pauseRatio = 1 - Double(voicedCount) / Double(activeFrameCount)
        let activeSampleCount = frameStarts[lastVoiced] + frameSize - frameStarts[firstVoiced]
        let activeDurationSec = Double(activeSampleCount) / sampleRate
        let phonationSec = activeDurationSec * (1 - pauseRatio)
        let wpm = activeDurationSec > 0 ? (Double(wordCount) / activeDurationSec) * 60 : 0

        var pitches: [Double] = []
        for i in activeRange where voiced[i] {
            let s = frameStarts[i]
            if let f0 = estimatePitch(samples, s, frameSize, sampleRate),
               f0 >= minF0Hz, f0 <= maxF0Hz {
                pitches.append(f0)
            }
        }
        let pitchMean = mean(pitches)
        // Higher = steadier pitch control; 1/(1+std) keeps it in a friendly 0..1-ish range.
        let pitchStability = pitches.count > 1 ? 1 / (1 + stdev(pitches)) : 0

        // Same fixed word count, excluding pauses: useful alongside speaking rate
        // without pretending waveform onsets are reliably equivalent to syllables.
        let articulationRate = phonationSec > 0 ? (Double(wordCount) / phonationSec) * 60 : 0

        return SpeechMetrics(wpm: wpm, pauseRatio: pauseRatio, pitchMean: pitchMean,
                             pitchStability: pitchStability, articulationRate: articulationRate,
                             durationSec: durationSec)
    }

    // MARK: - DSP primitives

    static func rms(_ data: [Float], _ start: Int, _ length: Int) -> Double {
        var sum = 0.0
        for i in start..<(start + length) {
            let v = Double(data[i])
            sum += v * v
        }
        return (sum / Double(length)).squareRoot()
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func stdev(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let m = mean(values)
        return mean(values.map { ($0 - m) * ($0 - m) }).squareRoot()
    }

    /// Standard time-domain autocorrelation pitch (F0) estimator for one frame.
    static func estimatePitch(_ data: [Float], _ start: Int, _ n: Int, _ sampleRate: Double) -> Double? {
        let minLag = Int(sampleRate / maxF0Hz)
        let maxLag = min(Int(sampleRate / minF0Hz), n - 1)
        guard minLag >= 1, maxLag > minLag else { return nil }

        var bestLag = -1
        var bestCorr = 0.0
        for lag in minLag...maxLag {
            var corr = 0.0
            for i in 0..<(n - lag) {
                corr += Double(data[start + i]) * Double(data[start + i + lag])
            }
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }
        return bestLag > 0 ? sampleRate / Double(bestLag) : nil
    }

    // MARK: - Frame geometry (shared with the live meter)

    /// Samples per analysis frame at `sampleRate`. The live meter and the
    /// end-of-recording analysis must frame identically, or the waveform a
    /// person watched would not correspond to the numbers they are shown.
    static func frameSize(at sampleRate: Double) -> Int {
        Int((sampleRate * frameMS) / 1000)
    }

    /// Samples between successive frame starts at `sampleRate`.
    static func hopSize(at sampleRate: Double) -> Int {
        Int((sampleRate * hopMS) / 1000)
    }
}

/// Fixed reference sentence read at every check-in, so results are comparable week to week.
enum Reference {
    static let sentence = String(localized: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow.")
    static var wordCount: Int { sentence.split(separator: " ").count }
}

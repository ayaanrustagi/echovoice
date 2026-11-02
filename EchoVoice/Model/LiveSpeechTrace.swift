import Foundation
import SwiftUI

/// One analysis frame, exactly as `SpeechAnalysis` frames it, surfaced while the
/// person is still speaking.
///
/// The frames here are not a decorative level meter. They are the same 25ms /
/// 10ms windows, the same short-time RMS, the same adaptive silence threshold,
/// and the same autocorrelation F0 estimator that produce the saved check-in
/// numbers — so what someone watches during a reading is what was measured.
struct LiveFrame: Identifiable, Equatable, Sendable {
    let index: Int
    /// Short-time RMS energy for this frame.
    let energy: Double
    /// Estimated fundamental frequency in Hz, or nil where the estimator found
    /// no reliable period (unvoiced frames, silence, or out-of-range results).
    let f0: Double?
    /// Whether this frame sits above the running adaptive silence threshold.
    let voiced: Bool

    var id: Int { index }
}

/// Streaming front end for `SpeechAnalysis`.
///
/// `SpeechAnalysis.analyze` is a one-shot function over a finished recording: it
/// can take the peak energy of the whole utterance before deciding what counts
/// as silence. A live meter cannot — it has to decide frame by frame, before the
/// loudest part may have happened yet. So this type tracks a *running* peak and
/// applies the same `silenceThresholdRatio` against it, then retro-corrects the
/// voiced flags already on screen when a new peak arrives. The result converges
/// on the same voiced/unvoiced split the final analysis produces.
///
/// Pitch is estimated on every `pitchDecimation`-th frame rather than all of
/// them. Autocorrelation over a 60–400 Hz lag range is the expensive part of the
/// pipeline, and 33 pitch points per second is already far more than a person
/// can read off a moving line. Energy stays per-frame because it is cheap and it
/// is what the voiced/unvoiced shading depends on.
@MainActor
@Observable
final class LiveSpeechTrace {
    /// Frames kept for display. At a 10ms hop this is the last ~4 seconds, which
    /// covers the reference sentence for most speakers without letting the
    /// buffer grow without bound during a long reading.
    static let displayFrameCapacity = 400

    /// Estimate pitch on every Nth frame. See the type comment.
    static let pitchDecimation = 3

    private(set) var frames: [LiveFrame] = []
    private(set) var peakEnergy: Double = 0
    private(set) var totalFrames: Int = 0
    private(set) var voicedFrames: Int = 0

    /// Whether enough frames exist for the waveform to mean anything yet.
    var hasSignal: Bool { peakEnergy > 0.0005 && totalFrames > 5 }

    /// Live pause ratio over the frames still in the display window. Shown as a
    /// running number, not saved — the stored value comes from the full-utterance
    /// analysis, which can trim leading and trailing silence properly.
    var windowPauseRatio: Double {
        guard !frames.isEmpty else { return 0 }
        let voiced = frames.reduce(0) { $0 + ($1.voiced ? 1 : 0) }
        return 1 - Double(voiced) / Double(frames.count)
    }

    /// Most recent usable pitch estimate, for the live readout.
    var currentF0: Double? {
        frames.reversed().first(where: { $0.voiced && $0.f0 != nil })?.f0
    }

    @ObservationIgnored private var carry: [Float] = []
    @ObservationIgnored private var sampleRate: Double = SpeechAnalysis.targetSampleRate
    @ObservationIgnored private var frameSize = 0
    @ObservationIgnored private var hopSize = 0

    func reset(sampleRate: Double = SpeechAnalysis.targetSampleRate) {
        self.sampleRate = sampleRate
        frameSize = SpeechAnalysis.frameSize(at: sampleRate)
        hopSize = SpeechAnalysis.hopSize(at: sampleRate)
        carry.removeAll(keepingCapacity: true)
        frames.removeAll(keepingCapacity: true)
        peakEnergy = 0
        totalFrames = 0
        voicedFrames = 0
    }

    /// Feed newly captured samples. Consumes as many whole frames as the carry
    /// buffer now allows and leaves the remainder for the next chunk, so no
    /// sample is analyzed twice and none is dropped at a chunk boundary.
    func append(_ chunk: [Float]) {
        guard frameSize > 0, hopSize > 0, !chunk.isEmpty else { return }
        carry.append(contentsOf: chunk)

        var start = 0
        var newFrames: [LiveFrame] = []
        while start + frameSize <= carry.count {
            let energy = SpeechAnalysis.rms(carry, start, frameSize)
            peakEnergy = max(peakEnergy, energy)

            let wantsPitch = totalFrames % Self.pitchDecimation == 0
            let f0 = wantsPitch
                ? SpeechAnalysis.estimatePitch(carry, start, frameSize, sampleRate)
                    .flatMap { $0 >= SpeechAnalysis.minF0Hz && $0 <= SpeechAnalysis.maxF0Hz ? $0 : nil }
                : nil

            newFrames.append(
                LiveFrame(
                    index: totalFrames,
                    energy: energy,
                    f0: f0,
                    voiced: energy > peakEnergy * SpeechAnalysis.silenceThresholdRatio
                )
            )
            totalFrames += 1
            start += hopSize
        }

        guard !newFrames.isEmpty else { return }
        carry.removeFirst(start)
        frames.append(contentsOf: newFrames)
        if frames.count > Self.displayFrameCapacity {
            frames.removeFirst(frames.count - Self.displayFrameCapacity)
        }
        rescoreVoicing()
    }

    /// Re-apply the silence threshold against the current running peak.
    ///
    /// Without this, every frame captured before the speaker's loudest moment
    /// keeps the verdict it got under a lower peak, and the early part of the
    /// waveform stays wrongly marked voiced. Re-scoring the visible window is
    /// cheap (a comparison per frame) and makes the live shading agree with the
    /// final analysis.
    private func rescoreVoicing() {
        let threshold = peakEnergy * SpeechAnalysis.silenceThresholdRatio
        var voiced = 0
        for index in frames.indices {
            let isVoiced = frames[index].energy > threshold
            if frames[index].voiced != isVoiced {
                frames[index] = LiveFrame(
                    index: frames[index].index,
                    energy: frames[index].energy,
                    f0: frames[index].f0,
                    voiced: isVoiced
                )
            }
            if isVoiced { voiced += 1 }
        }
        voicedFrames = voiced
    }
}

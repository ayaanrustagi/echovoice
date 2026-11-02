import Foundation

/// Checks a banked recording right after it is made, before it is saved.
///
/// A banked phrase may end up being the last recording of someone's natural
/// voice. A flaw discovered months later, after speech has changed, cannot be
/// fixed by recording again. So this runs as soon as Stop is pressed and flags
/// the problems that ruin a recording but are easy to miss on a phone speaker:
/// clipping, a level too low to hear, background noise close to the speech
/// level, and speech cut off at either end.
///
/// It reuses the journal's framing (25 ms windows, 10 ms hop, short-time RMS),
/// so every number traces back to the same measurement. Levels are dBFS —
/// relative to the microphone's full scale, not a calibrated sound level.
///
/// Advisory only: the person can always save anyway. A quiet or breathy voice
/// is still their voice, and refusing to save it would be worse than any flaw.
enum RecordingQuality {
    enum Issue: String, CaseIterable, Equatable, Sendable {
        case noSpeech
        case clipped
        case tooQuiet
        case noisy
        case cutOffStart
        case cutOffEnd

        var title: String {
            switch self {
            case .noSpeech: return String(localized: "No speech heard")
            case .clipped: return String(localized: "Distorted (too loud)")
            case .tooQuiet: return String(localized: "Very quiet")
            case .noisy: return String(localized: "Background noise")
            case .cutOffStart: return String(localized: "Start may be cut off")
            case .cutOffEnd: return String(localized: "End may be cut off")
            }
        }

        var advice: String {
            switch self {
            case .noSpeech: return String(localized: "Check the microphone isn't covered, then try again.")
            case .clipped: return String(localized: "Hold the phone a little farther from your mouth.")
            case .tooQuiet: return String(localized: "Hold the phone closer, about a hand's width away.")
            case .noisy: return String(localized: "Move somewhere quieter, or turn off a fan or TV.")
            case .cutOffStart: return String(localized: "After tapping Record, wait a beat before speaking.")
            case .cutOffEnd: return String(localized: "Wait a beat after speaking before tapping Stop.")
            }
        }
    }

    struct Report: Equatable, Sendable {
        var issues: [Issue]
        /// Loud end of the recording: 95th-percentile frame level, dBFS.
        var speechLevelDB: Double
        /// Quiet end of the recording: 10th-percentile frame level, dBFS.
        var noiseFloorDB: Double
        /// Share of samples at or beyond the clipping level, 0...1.
        var clippedFraction: Double
        /// Whether the noise check ran. It is skipped when speech fills the whole
        /// recording, because then there is no quiet stretch to measure noise in.
        var measuredNoise: Bool

        var snrDB: Double { speechLevelDB - noiseFloorDB }
        var isClear: Bool { issues.isEmpty }
    }

    /// A sample this close to full scale is treated as clipped.
    static let clipSampleLevel: Float = 0.98
    /// More than 0.1% clipped samples is audible distortion.
    static let maxClippedFraction = 0.001
    /// Below this the speech itself is hard to hear on a phone speaker.
    static let minSpeechLevelDB = -36.0
    /// Below this nothing resembling speech was captured.
    static let noSpeechLevelDB = -50.0
    /// Speech should sit at least this far above the room.
    static let minSNRDB = 15.0
    /// How much of each end is checked for speech that was cut off.
    static let edgeMS = 40.0
    /// An edge counts as speech when it is within 14 dB of the speech level…
    static let edgeSpeechRatio = 0.2
    /// …and clearly above the quiet part of the recording (+6 dB). The second
    /// condition is what separates "still talking" from "a noisy room": in a
    /// noisy room the edges are just more of the room.
    static let edgeNoiseRatio = 2.0

    private static let floorDB = -120.0

    static func analyze(samples: [Float], sampleRate: Double) -> Report {
        let frameSize = SpeechAnalysis.frameSize(at: sampleRate)
        let hopSize = SpeechAnalysis.hopSize(at: sampleRate)
        guard frameSize > 0, hopSize > 0, samples.count >= frameSize * 3 else {
            return Report(issues: [.noSpeech], speechLevelDB: floorDB, noiseFloorDB: floorDB,
                          clippedFraction: 0, measuredNoise: false)
        }

        var energies: [Double] = []
        var start = 0
        while start + frameSize <= samples.count {
            energies.append(SpeechAnalysis.rms(samples, start, frameSize))
            start += hopSize
        }

        let sorted = energies.sorted()
        let speech = percentile(sorted, 0.95)
        let noise = percentile(sorted, 0.10)
        let clipped = Double(samples.lazy.filter { abs($0) >= clipSampleLevel }.count) / Double(samples.count)

        var report = Report(issues: [], speechLevelDB: dB(speech), noiseFloorDB: dB(noise),
                            clippedFraction: clipped, measuredNoise: false)

        // Nothing else is meaningful when there is no speech to judge.
        guard report.speechLevelDB >= noSpeechLevelDB else {
            report.issues = [.noSpeech]
            return report
        }

        if clipped > maxClippedFraction { report.issues.append(.clipped) }
        if report.speechLevelDB < minSpeechLevelDB { report.issues.append(.tooQuiet) }

        let edgeFrames = max(1, Int(edgeMS / SpeechAnalysis.hopMS))
        func isSpeech(_ edge: Double) -> Bool {
            edge > speech * edgeSpeechRatio && edge > noise * edgeNoiseRatio
        }
        let startCut = isSpeech(mean(energies.prefix(edgeFrames)))
        let endCut = isSpeech(mean(energies.suffix(edgeFrames)))
        if startCut { report.issues.append(.cutOffStart) }
        if endCut { report.issues.append(.cutOffEnd) }

        // The noise floor is the quiet end of the recording. When speech runs
        // from the first frame to the last, the quiet end is just softer speech,
        // and calling that "noise" would blame the room for a timing problem.
        if !(startCut && endCut) {
            report.measuredNoise = true
            if report.snrDB < minSNRDB { report.issues.append(.noisy) }
        }
        return report
    }

    static func dB(_ rms: Double) -> Double {
        rms > 0 ? max(floorDB, 20 * log10(rms)) : floorDB
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[Int((Double(sorted.count - 1) * p).rounded())]
    }

    private static func mean<C: Collection>(_ values: C) -> Double where C.Element == Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

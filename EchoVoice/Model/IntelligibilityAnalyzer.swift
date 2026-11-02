import AVFoundation
import Foundation
import Speech

/// On-device intelligibility scoring using Apple's speech recognizer.
///
/// The DSP metrics in `SpeechAnalysis` measure *how* someone speaks — rate,
/// pauses, pitch steadiness. Those are proxies. This measures the thing families
/// actually care about: **how much of the sentence came through.**
///
/// Because the reference sentence is fixed and known, the transcript can be
/// compared against ground truth by word-level edit distance. No training data,
/// no labels, no server — Apple's recognizer is a neural model that already ships
/// on the device, and `requiresOnDeviceRecognition` keeps every sample local.
///
/// Honest about what this is:
/// ASR is trained largely on typical speech, so its absolute accuracy on
/// dysarthric speech will not match a human listener's. That bias is roughly
/// constant for one speaker and one sentence, which is exactly why this is only
/// ever compared against the same person's earlier readings — never to a
/// population norm, never as a screening result, never as a diagnosis. It is
/// "how much did the recognizer catch this week versus last week," nothing more.
enum IntelligibilityAnalyzer {
    struct Result: Equatable, Sendable {
        /// Word accuracy against the reference sentence, 0...1.
        var score: Double
        /// What the recognizer heard, for the person to see for themselves.
        var transcript: String
        var wordsMatched: Int
        var wordsExpected: Int
    }

    enum Availability {
        case ready
        case notAuthorized
        case unavailableOnDevice
    }

    /// Ask once for speech-recognition permission. Recording still works without
    /// it — intelligibility is simply skipped rather than blocking the check-in.
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static var availability: Availability {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return .notAuthorized }
        guard let recognizer = OnDeviceRecognition.recognizer(),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { return .unavailableOnDevice }
        return .ready
    }

    /// Transcribe the recorded samples and score them against `target`.
    /// Returns nil when recognition is unavailable or produced nothing usable —
    /// callers treat that as "no intelligibility reading this week," not an error.
    static func analyze(samples: [Float], sampleRate: Double, target: String) async -> Result? {
        guard case .ready = availability else { return nil }
        guard !samples.isEmpty else { return nil }
        guard let recognizer = OnDeviceRecognition.recognizer() else { return nil }

        guard let buffer = makeBuffer(from: samples, sampleRate: sampleRate) else { return nil }

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Non-negotiable: recordings of someone's voice must never leave the device.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.append(buffer)
        request.endAudio()

        let transcript = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if error != nil {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }
                if let result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }

        guard let transcript else { return nil }
        return score(transcript: transcript, against: target)
    }

    /// Compare a transcript to the expected sentence.
    static func score(transcript: String, against target: String) -> Result {
        let heard = normalize(transcript)
        let expected = normalize(target)

        guard !expected.isEmpty else {
            return Result(score: 0, transcript: transcript, wordsMatched: 0, wordsExpected: 0)
        }

        let distance = wordEditDistance(heard, expected)
        // Edit distance can exceed the expected length when the recognizer emits
        // extra words, so clamp rather than letting the score go negative.
        let accuracy = max(0, 1 - Double(distance) / Double(expected.count))

        return Result(
            score: accuracy,
            transcript: transcript,
            wordsMatched: max(0, expected.count - distance),
            wordsExpected: expected.count
        )
    }

    // MARK: - Internals

    /// Lowercase, strip punctuation, split on whitespace. Punctuation and casing
    /// are artifacts of the recognizer's formatting, not of how clearly someone spoke.
    private static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Levenshtein distance over words (not characters): substitutions, insertions
    /// and deletions of whole words, which is how intelligibility is scored clinically.
    private static func wordEditDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        // Single-row DP; only the previous row is ever needed.
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                let insertion = current[j - 1] + 1
                let deletion = previous[j] + 1
                current[j] = min(substitution, insertion, deletion)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    private static func makeBuffer(from samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

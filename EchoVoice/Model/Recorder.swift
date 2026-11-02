// @preconcurrency: AVFAudio predates Sendable; the converter's input block is
// synchronous and the buffer never escapes it, so the capture is safe.
@preconcurrency import AVFoundation
import SwiftUI

/// Records the fixed reference sentence and extracts speech metrics entirely
/// on-device via `SpeechAnalysis`. Nothing is uploaded or stored as audio — the
/// waveform is analyzed in memory and only the resulting numbers are kept.
///
/// Concurrency: the audio tap runs off the main actor. It captures only local,
/// non-isolated values (the converter + target format), builds a `Sendable`
/// `[Float]` chunk, and hops to the main actor to append — so no `@MainActor`
/// state is touched from the audio thread.
@MainActor
@Observable
final class Recorder {
    enum State: Equatable { case idle, recording, analyzing }

    private(set) var state: State = .idle
    var errorMessage: String?

    /// Frame-by-frame view of the audio as it is captured. Same framing and
    /// same estimators as the saved analysis — see `LiveSpeechTrace`.
    let trace = LiveSpeechTrace()

    /// Wall-clock cost of the last full-utterance analysis, in milliseconds.
    /// Surfaced in the UI as a measured number rather than a claim: it is the
    /// simplest honest evidence that the DSP ran here and not on a server.
    private(set) var lastAnalysisMS: Double?

    private let engine = AVAudioEngine()
    private var samples16k: [Float] = []

    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: SpeechAnalysis.targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Prompt for mic permission (iOS 17 API). Returns whether granted.
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        guard state == .idle else { return }
        samples16k.removeAll()
        trace.reset()
        lastAnalysisMS = nil
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let target = Self.targetFormat
        let converter = AVAudioConverter(from: inputFormat, to: target)

        // Tap block is not @Sendable; it captures only locals + appends via a
        // main-actor Task, never touching this object's isolated state directly.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let converter,
                  let chunk = Self.convertToChunk(buffer, using: converter, target: target)
            else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.samples16k.append(contentsOf: chunk)
                self.trace.append(chunk)
            }
        }

        engine.prepare()
        try engine.start()
        state = .recording
    }

    /// Stop capture, run the DSP, and hand the metrics back.
    func finish() -> SpeechMetrics? {
        guard state == .recording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        state = .analyzing

        let startedAt = ProcessInfo.processInfo.systemUptime
        let metrics = SpeechAnalysis.analyze(
            samples: samples16k,
            sampleRate: SpeechAnalysis.targetSampleRate,
            wordCount: Reference.wordCount
        )
        lastAnalysisMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
        state = .idle
        return metrics
    }

    /// Stop capture, run the DSP, then transcribe the same audio on-device to
    /// score intelligibility. Intelligibility is best-effort: if recognition is
    /// unavailable or unauthorized the check-in still completes with metrics only.
    func finishWithIntelligibility() async -> (metrics: SpeechMetrics, intelligibility: IntelligibilityAnalyzer.Result?)? {
        guard state == .recording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        state = .analyzing

        let captured = samples16k
        // Times the signal processing alone. Speech recognition is a separate
        // system with its own latency, so folding it in would misreport what the
        // DSP costs.
        let startedAt = ProcessInfo.processInfo.systemUptime
        let metrics = SpeechAnalysis.analyze(
            samples: captured,
            sampleRate: SpeechAnalysis.targetSampleRate,
            wordCount: Reference.wordCount
        )
        lastAnalysisMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000

        let intelligibility = await IntelligibilityAnalyzer.analyze(
            samples: captured,
            sampleRate: SpeechAnalysis.targetSampleRate,
            target: Reference.sentence
        )

        state = .idle
        return (metrics, intelligibility)
    }

    /// Convert one input buffer to 16kHz mono float samples. Pure/nonisolated:
    /// touches no actor state, so it's safe to call from the audio thread.
    private nonisolated static func convertToChunk(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        target: AVAudioFormat
    ) -> [Float]? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}

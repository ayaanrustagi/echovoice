@preconcurrency import AVFoundation
import SwiftUI

/// A one-off, 1.5-second reading of how loud the room is, for adaptive volume
/// when Listen mode isn't running. Only a level is kept; no audio is stored.
@MainActor
@Observable
final class RoomCheck {
    static let duration: Duration = .milliseconds(1500)

    private(set) var isMeasuring = false
    private(set) var errorMessage: String?

    private let engine = AVAudioEngine()

    func measure() async -> AdaptiveVolume.Reading? {
        guard !isMeasuring else { return nil }
        errorMessage = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = String(localized: "Checking the room needs microphone access.")
            return nil
        }
        isMeasuring = true
        defer { isMeasuring = false }

        let levels = LevelCollector()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                levels.add(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            errorMessage = String(localized: "Couldn't use the microphone. Try again.")
            return nil
        }

        try? await Task.sleep(for: Self.duration)
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let noise = AdaptiveVolume.roomNoiseDB(frameRMS: levels.values) else {
            errorMessage = String(localized: "Didn't get a reading. Try again.")
            return nil
        }
        return AdaptiveVolume.Reading(noiseDB: noise, takenAt: .now)
    }
}

/// Collects per-buffer RMS on the audio thread.
private final class LevelCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var levels: [Double] = []

    var values: [Double] {
        lock.lock(); defer { lock.unlock() }
        return levels
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = Double((sum / Float(count)).squareRoot())
        lock.lock(); levels.append(rms); lock.unlock()
    }
}

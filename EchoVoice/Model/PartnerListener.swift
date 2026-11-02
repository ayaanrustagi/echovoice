// @preconcurrency: AVFAudio and Speech predate Sendable. The tap closure only
// touches `TapBridge`, which guards its state with a lock.
@preconcurrency import AVFoundation
@preconcurrency import Speech
import SwiftUI

/// Listens to a conversation partner and transcribes them on the device, so
/// EchoVoice can offer replies to what they just said (`PartnerReplySuggester`).
///
/// Privacy rules this keeps:
/// - Recognition must run on the device. If the device can't, Listen stays off;
///   it never falls back to Apple's server recognizer.
/// - No audio is stored. Buffers go to the recognizer and are dropped. Only the
///   latest sentence is kept, in memory, and cleared when Listen closes.
/// - The microphone is on only while the Listen screen is open and the app is
///   in the foreground, and iOS shows its microphone indicator the whole time.
///
/// While EchoVoice itself is speaking, buffers are ignored, so the person's own
/// replies are never transcribed back as if the partner had said them.
@MainActor
@Observable
final class PartnerListener {
    enum State: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    /// Shared with `Speaker`, so speaking never changes the session options
    /// underneath a running microphone.
    nonisolated static let sessionOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP]

    /// A pause this long ends the partner's turn.
    static let turnPause: Duration = .milliseconds(1200)
    /// Room level is judged over roughly the last five seconds (2048-sample
    /// buffers at 48 kHz are about 43 ms each).
    static let roomWindow = 120

    private(set) var state: State = .idle
    /// Words of the current turn, updating as the partner speaks.
    private(set) var liveText = ""
    /// The partner's last complete turn.
    private(set) var lastHeard: String?

    /// Called when the partner finishes a turn.
    var onTurn: ((String) -> Void)?
    /// Called with a fresh room-noise reading about once a second.
    var onRoomReading: ((AdaptiveVolume.Reading) -> Void)?

    private let engine = AVAudioEngine()
    private let bridge = TapBridge()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionFailures: [Date] = []
    private var task: SFSpeechRecognitionTask?
    private var turnTimer: Task<Void, Never>?
    private var roomFrames: [Double] = []
    private var lastRoomReport = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var isSuppressed = false
    /// True while `start` waits on permission prompts. A second call in that
    /// window would install a second microphone tap, which AVAudioEngine
    /// treats as a fatal error.
    private var isStarting = false

    /// Ask for both permissions, check on-device support, then start.
    func start() async {
        guard state != .listening, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .unavailable(String(localized: "Listen needs microphone access. Allow it in iPhone Settings › EchoVoice."))
            return
        }
        guard await IntelligibilityAnalyzer.requestAuthorization() else {
            state = .unavailable(String(localized: "Listen needs speech recognition. Allow it in iPhone Settings › EchoVoice."))
            return
        }
        guard let recognizer = OnDeviceRecognition.recognizer(),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable(String(localized: "This device can't recognize speech on its own, so Listen stays off. EchoVoice never sends audio to a server."))
            return
        }
        self.recognizer = recognizer
        recognitionFailures = []

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: Self.sessionOptions)
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let bridge = self.bridge
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                let level = bridge.receive(buffer)
                guard let level else { return }
                Task { @MainActor [weak self] in self?.noteLevel(level) }
            }
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            state = .unavailable(String(localized: "Microphone is busy. If you're on a call, end it, then open Listen again."))
            return
        }

        observeInterruptions()
        state = .listening
        beginTurn()
    }

    /// Turn the microphone off and forget what was heard.
    func stop() {
        turnTimer?.cancel()
        turnTimer = nil
        task?.cancel()
        task = nil
        bridge.setRequest(nil)
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        liveText = ""
        lastHeard = nil
        roomFrames = []
        if state == .listening { state = .idle }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ignore the microphone while EchoVoice speaks, then start a fresh turn.
    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        bridge.setSuppressed(suppressed)
        guard state == .listening else { return }
        if suppressed {
            // Drop any half-heard words: they may be EchoVoice's own voice.
            turnTimer?.cancel()
            task?.cancel()
            task = nil
            bridge.setRequest(nil)
            liveText = ""
        } else {
            beginTurn()
        }
    }

    func clearHeard() {
        lastHeard = nil
        liveText = ""
    }

    #if DEBUG
    /// `-EchoVoiceListenSample "…"`: behave as if the partner said this, so
    /// the reply layout can be checked where recognition isn't available.
    func simulateTurn(_ text: String) {
        lastHeard = text
        onTurn?(text)
    }
    #endif

    // MARK: - Turns

    private func beginTurn() {
        guard state == .listening, !isSuppressed, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        bridge.setRequest(request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, failed: failed, request: request)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, request: SFSpeechAudioBufferRecognitionRequest) {
        // A late callback from a turn that already ended or was dropped.
        guard bridge.isCurrent(request) else { return }
        if let text, !text.isEmpty {
            liveText = text
            recognitionFailures = []
            scheduleTurnEnd()
        }
        if failed && liveText.isEmpty {
            // The recognizer gave up with nothing heard (it does this after a
            // long silence, or when briefly unavailable). Retry after a pause
            // rather than at once, so a persistent failure can't spin.
            let now = Date.now
            recognitionFailures = recognitionFailures.filter { now.timeIntervalSince($0) < 10 } + [now]
            if recognitionFailures.count >= 3 {
                stop()
                state = .unavailable(String(localized: "listen.recognitionFailed"))
            } else {
                restartAfterFailure()
            }
        } else if isFinal || failed {
            endTurn()
        }
    }

    private func restartAfterFailure() {
        turnTimer?.cancel()
        task?.cancel()
        task = nil
        bridge.setRequest(nil)
        turnTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.beginTurn()
        }
    }

    private func scheduleTurnEnd() {
        turnTimer?.cancel()
        turnTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.turnPause)
            guard !Task.isCancelled else { return }
            self?.endTurn()
        }
    }

    private func endTurn() {
        turnTimer?.cancel()
        turnTimer = nil
        let heard = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        task = nil
        bridge.setRequest(nil)
        liveText = ""
        if !heard.isEmpty {
            lastHeard = heard
            onTurn?(heard)
        }
        beginTurn()
    }

    // MARK: - Room level

    private func noteLevel(_ rms: Double) {
        roomFrames.append(rms)
        if roomFrames.count > Self.roomWindow { roomFrames.removeFirst(roomFrames.count - Self.roomWindow) }
        guard Date.now.timeIntervalSince(lastRoomReport) >= 1,
              let noise = AdaptiveVolume.roomNoiseDB(frameRMS: roomFrames) else { return }
        lastRoomReport = .now
        onRoomReading?(AdaptiveVolume.Reading(noiseDB: noise, takenAt: .now))
    }

    // MARK: - Interruptions

    private func observeInterruptions() {
        let center = NotificationCenter.default
        // A phone call or Siri takes the microphone; stop rather than resume
        // listening to something the person didn't choose to share.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        })
        // A route change (headphones, Bluetooth) rebuilds the input; the engine
        // stops, so restart it with the new format.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                self.stop()
                await self.start()
            }
        })
    }
}

/// The only state the audio thread touches. Lock-protected so the tap can
/// feed the current request without hopping to the main actor per buffer.
private final class TapBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var suppressed = false

    func setRequest(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request?.endAudio()
        request = newRequest
        lock.unlock()
    }

    func setSuppressed(_ value: Bool) {
        lock.lock(); suppressed = value; lock.unlock()
    }

    func isCurrent(_ candidate: SFSpeechAudioBufferRecognitionRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return request === candidate
    }

    /// Feed the recognizer and return this buffer's RMS level for the room
    /// reading. Returns nil while EchoVoice is speaking: its own voice is not
    /// the room, and must not be transcribed as the partner.
    func receive(_ buffer: AVAudioPCMBuffer) -> Double? {
        lock.lock()
        let isSuppressed = suppressed
        if !isSuppressed { request?.append(buffer) }
        lock.unlock()
        guard !isSuppressed, let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        return Double((sum / Float(count)).squareRoot())
    }
}

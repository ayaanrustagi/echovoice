import AVFoundation
import NaturalLanguage
import SwiftUI

@MainActor
@Observable
final class Speaker: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    enum PersonalVoiceState {
        case unavailable
        case notAuthorized
        case authorized
    }

    private(set) var personalVoiceState: PersonalVoiceState = .notAuthorized
    private(set) var speakingPhraseID: UUID?

    /// Whether audio is playing right now, for either a banked recording or
    /// synthesized text.
    ///
    /// `speakingPhraseID` only covers board phrases; free text spoken from Type
    /// or the workspace has no phrase to identify. The partner display needs to
    /// distinguish "still writing" from "speaking now" for both, so this is
    /// tracked separately rather than inferred from the synthesizer, whose own
    /// `isSpeaking` flag is not set synchronously (see `speakRawTextAndWait`).
    private(set) var isSpeaking = false
    /// What is being said right now, for the on-screen "Speaking" status.
    private(set) var speakingText: String?
    var statusExplanation: String?
    var isChecking: Bool = false

    /// Raise speech volume in a noisy room (see `AdaptiveVolume`).
    var adaptsToRoom: Bool = UserDefaults.standard.bool(forKey: "echovoice.adaptiveVolume") {
        didSet { UserDefaults.standard.set(adaptsToRoom, forKey: "echovoice.adaptiveVolume") }
    }
    /// Latest on-device room reading, from Listen mode or a room check.
    var roomReading: AdaptiveVolume.Reading?

    /// Set while Listen mode has the microphone. Playback then keeps a
    /// play-and-record session; switching to playback-only would cut the
    /// microphone off mid-conversation every time EchoVoice spoke.
    var keepsMicrophoneOpen = false

    /// The volume actually used for `requested`, after any room adjustment.
    func effectiveVolume(_ requested: Float) -> Float {
        adaptsToRoom ? AdaptiveVolume.volume(base: requested, reading: roomReading) : requested
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var personalVoice: AVSpeechSynthesisVoice?
    private var activeSynthUtterance: AVSpeechUtterance?

    /// Renders one utterance to memory at launch and discards it. The first
    /// real utterance otherwise waits a second or more for the voice to load,
    /// long enough that someone taps again thinking nothing happened.
    /// `write` synthesizes without playing anything or touching the audio
    /// session, so launching the app never interrupts other audio.
    private let warmUpSynthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
        let warmUp = AVSpeechUtterance(string: String(localized: "Ready."))
        warmUp.voice = systemVoice(for: AppLanguage.code)
        warmUpSynthesizer.write(warmUp) { _ in }
        loadPersonalVoiceIfAllowed()
    }

    /// Picks up a Personal Voice the person already allowed, so it is on from
    /// launch instead of waiting for them to tap Check. Never prompts.
    private func loadPersonalVoiceIfAllowed() {
        guard #available(iOS 17.0, *),
              AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized,
              let pv = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.voiceTraits.contains(.isPersonalVoice) })
        else { return }
        personalVoice = pv
        personalVoiceState = .authorized
        statusExplanation = String(localized: "✓ Apple Personal Voice '%@' is active!", defaultValue: "✓ Apple Personal Voice '\(String(describing: pv.name))' is active!")
    }

    func requestPersonalVoice() {
        isChecking = true
        statusExplanation = String(localized: "Checking iOS Personal Voice status...")

        if #available(iOS 17.0, *) {
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    self.isChecking = false
                    switch status {
                    case .authorized:
                        let voices = AVSpeechSynthesisVoice.speechVoices()
                        self.personalVoice = voices.first { $0.voiceTraits.contains(.isPersonalVoice) }

                        if let pv = self.personalVoice {
                            self.personalVoiceState = .authorized
                            self.statusExplanation = String(localized: "✓ Apple Personal Voice '%@' is active!", defaultValue: "✓ Apple Personal Voice '\(String(describing: pv.name))' is active!")
                        } else {
                            self.personalVoiceState = .unavailable
                            self.statusExplanation = String(localized: "Permission granted! However, no Personal Voice was created on this iPhone yet. Create one in iPhone Settings › Accessibility › Personal Voice.")
                        }
                    case .denied:
                        self.personalVoiceState = .notAuthorized
                        self.statusExplanation = String(localized: "Permission denied. Allow EchoVoice access in iPhone Settings › Privacy & Security › Personal Voice.")
                    case .unsupported:
                        self.personalVoiceState = .unavailable
                        self.statusExplanation = String(localized: "Personal Voice isn’t available on this device.")
                    case .notDetermined:
                        self.personalVoiceState = .notAuthorized
                        self.statusExplanation = String(localized: "Permission not determined. Please tap Check for Personal Voice again.")
                    @unknown default:
                        self.personalVoiceState = .notAuthorized
                        self.statusExplanation = String(localized: "Status unknown.")
                    }
                }
            }
        } else {
            isChecking = false
            self.personalVoiceState = .unavailable
            self.statusExplanation = String(localized: "Apple Personal Voice requires iOS 17.0 or newer.")
        }
    }

    var isUsingPersonalVoice: Bool { personalVoice != nil }

    /// Immediately stop any ongoing audio file playback or TTS utterance
    func stopSpeaking() {
        // `isSpeaking` can still be false just after `speak` enqueues an
        // utterance. Stopping only when it is true leaves that queued sentence
        // alive, so the next tap reads over it or starts partway through it.
        // Stop the synthesizer unconditionally, including its pending queue.
        activeSynthUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil
        speakingPhraseID = nil
        isSpeaking = false
        speakingText = nil
        // Release anyone awaiting this utterance. Doing it here as well as in the
        // delegate matters: stopping a synthesizer that isn't currently speaking
        // produces no callback, which would otherwise strand the waiter forever.
        finishPendingUtterance()
    }

    // MARK: Awaiting an utterance

    private var utteranceContinuation: CheckedContinuation<Void, Never>?
    private var awaitedUtterance: AVSpeechUtterance?

    private func finishPendingUtterance(for utterance: AVSpeechUtterance? = nil) {
        if let utterance, awaitedUtterance !== utterance { return }
        guard let continuation = utteranceContinuation else { return }
        utteranceContinuation = nil
        awaitedUtterance = nil
        continuation.resume()
    }

    /// Speak `text` and return only once it has finished or been stopped.
    ///
    /// Needed for anything that repeats an utterance: `AVSpeechSynthesizer` does
    /// not report `isSpeaking == true` synchronously when `speak` returns, so
    /// polling that flag reports "done" instantly and the repetitions collapse
    /// into each other. Waiting on the delegate is the only reliable signal.
    func speakRawTextAndWait(_ text: String, rate: Float = 0.9, volume: Float = 1.0) async {
        // Clear any previous utterance first, so the continuation set below can't
        // be resumed by the *old* utterance's cancellation callback.
        stopSpeaking()
        preparePlaybackSession()
        let utterance = makeUtterance(text, rate: rate, volume: effectiveVolume(volume))

        isSpeaking = true
        speakingText = text
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            utteranceContinuation = continuation
            awaitedUtterance = utterance
            activeSynthUtterance = utterance
            synthesizer.speak(utterance)
        }
        if activeSynthUtterance === utterance {
            activeSynthUtterance = nil
            isSpeaking = false
            speakingText = nil
        }
    }

    func speak(_ phrase: Phrase, rate: Float = 0.9, volume: Float = 1.0) {
        // Dwell or an unsteady double tap can select the same tile twice before
        // the first sentence ends. Keep that sentence intact; a different tile
        // still interrupts immediately.
        if isSpeaking && speakingPhraseID == phrase.id {
            #if DEBUG
            if Self.logsSpeech { print("ECHOVOICE_SPEECH request ignored-repeat text=\"\(phrase.text.prefix(40))\"") }
            #endif
            return
        }
        #if DEBUG
        if Self.logsSpeech { print("ECHOVOICE_SPEECH request phrase text=\"\(phrase.text.prefix(40))\" interrupting=\(isSpeaking)") }
        #endif
        stopSpeaking()
        let volume = effectiveVolume(volume)

        preparePlaybackSession()
        speakingPhraseID = phrase.id
        isSpeaking = true
        speakingText = phrase.text

        // 1. Play banked recording in real voice if available on disk
        if let audioFileName = phrase.audioFileName {
            let audioURL = AudioFileManager.getURL(for: audioFileName)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                do {
                    let player = try AVAudioPlayer(contentsOf: audioURL)
                    player.delegate = self
                    player.volume = volume
                    if player.play() {
                        audioPlayer = player
                        return
                    }
                } catch {
                    // Fall back to TTS if audio file fails to load
                }
            }
        }

        preparePlaybackSession()
        let utterance = makeUtterance(phrase.text, rate: rate, volume: volume)
        activeSynthUtterance = utterance
        synthesizer.speak(utterance)
    }

    func speakRawText(_ text: String, rate: Float = 0.9, volume: Float = 1.0) {
        if isSpeaking && activeSynthUtterance?.speechString == text {
            #if DEBUG
            if Self.logsSpeech { print("ECHOVOICE_SPEECH request ignored-repeat text=\"\(text.prefix(40))\"") }
            #endif
            return
        }
        #if DEBUG
        if Self.logsSpeech { print("ECHOVOICE_SPEECH request raw text=\"\(text.prefix(40))\" interrupting=\(isSpeaking)") }
        #endif
        stopSpeaking()
        isSpeaking = true
        speakingText = text
        enqueueUtterance(text, rate: rate, volume: effectiveVolume(volume))
    }

    /// Configure and speak one utterance. Does *not* stop current audio first —
    /// callers decide that, so `speakRawTextAndWait` can stop before it installs
    /// its continuation rather than after.
    private func enqueueUtterance(_ text: String, rate: Float, volume: Float) {
        preparePlaybackSession()
        let utterance = makeUtterance(text, rate: rate, volume: volume)
        activeSynthUtterance = utterance
        synthesizer.speak(utterance)
    }

    private func preparePlaybackSession() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        if keepsMicrophoneOpen {
            // Same category and options Listen started with, so this is a no-op
            // while it runs, and still a working session if Listen couldn't start.
            try? audioSession.setCategory(.playAndRecord, mode: .default, options: PartnerListener.sessionOptions)
            try? audioSession.setActive(true)
            return
        }
        try? audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func makeUtterance(_ text: String, rate: Float, volume: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = volume
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.10

        // Personal Voice is used only for text in its own language: an English
        // Personal Voice reading Spanish is close to unintelligible.
        let language = language(of: text)
        if let pv = personalVoice, pv.language.hasPrefix(language) {
            utterance.voice = pv
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        } else {
            utterance.voice = systemVoice(for: language)
            let clampedRate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
            utterance.rate = clampedRate
        }

        return utterance
    }

    // MARK: Language

    /// The board's language ("en" or "es"). Each utterance is still checked on
    /// its own, so a bilingual family's board can hold both and every phrase is
    /// read in the voice that matches it.
    var boardLanguage: String = AppLanguage.code

    /// Picks English or Spanish for `text`, on device, leaning toward the
    /// board's language because short words ("No", "TV") read the same in both.
    func language(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .spanish]
        recognizer.languageHints = boardLanguage == "es"
            ? [.spanish: 0.7, .english: 0.3]
            : [.english: 0.7, .spanish: 0.3]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let es = hypotheses[.spanish] ?? 0
        let en = hypotheses[.english] ?? 0
        // Only switch away from the board's language on a clear margin.
        if boardLanguage == "es" { return en > es + 0.3 ? "en" : "es" }
        return es > en + 0.3 ? "es" : "en"
    }

    private func systemVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = language == "es" ? ["es-MX", "es-US"] : ["en-US"]
        for code in candidates {
            if let voice = AVSpeechSynthesisVoice(language: code) { return voice }
        }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(language) }
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audioPlayer === player else { return }
            self.speakingPhraseID = nil
            self.isSpeaking = false
            self.speakingText = nil
            self.audioPlayer = nil
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    #if DEBUG
    /// `-EchoVoiceLogSpeech` prints every synthesizer event, so repeated-tap
    /// behaviour can be checked from a log: each utterance must start at
    /// character 0, and a new one must never start before the old one ended.
    nonisolated static let logsSpeech = ProcessInfo.processInfo.arguments.contains("-EchoVoiceLogSpeech")

    nonisolated private static func log(_ event: String, _ utterance: AVSpeechUtterance) {
        guard logsSpeech else { return }
        let id = String(UInt(bitPattern: ObjectIdentifier(utterance).hashValue) % 100_000)
        print("ECHOVOICE_SPEECH t=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) \(event) u=\(id) text=\"\(utterance.speechString.prefix(40))\"")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Self.log("start", utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard Self.logsSpeech else { return }
        Self.log("range=\(characterRange.location)", utterance)
    }
    #endif

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        #if DEBUG
        Self.log("finish", utterance)
        #endif
        Task { @MainActor in
            if self.activeSynthUtterance === utterance {
                self.speakingPhraseID = nil
                self.isSpeaking = false
                self.speakingText = nil
                self.activeSynthUtterance = nil
            }
            self.finishPendingUtterance(for: utterance)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        #if DEBUG
        Self.log("cancel", utterance)
        #endif
        Task { @MainActor in
            if self.activeSynthUtterance === utterance {
                self.speakingPhraseID = nil
                self.isSpeaking = false
                self.speakingText = nil
                self.activeSynthUtterance = nil
            }
            self.finishPendingUtterance(for: utterance)
        }
    }
}

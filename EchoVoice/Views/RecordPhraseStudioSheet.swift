import AVFoundation
import SwiftUI

/// Dedicated Voice Banking Recording Studio Modal.
/// Displays clear reading instructions, teleprompter sentence text,
/// live microphone waveform level meter, audio playback preview, and save controls.
struct RecordPhraseStudioSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    let phrase: Phrase

    @State private var isRecording = false
    @State private var isPlayingPreview = false
    @State private var recordedURL: URL?
    @State private var recordingTime: Double = 0.0
    @State private var audioLevel: CGFloat = 0.2

    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?
    @State private var errorMessage: String?
    @State private var quality: RecordingQuality.Report?
    @State private var qualityMS: Double?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                // Header & Phrase Info
                VStack(spacing: 8) {
                    PhraseGlyph(symbol: phrase.symbol, color: Palette.forest)
                        .scaleEffect(1.4)
                        .padding(16)
                        .background(Palette.forest.opacity(0.1), in: .circle)

                    Text(phrase.label)
                        .font(EchoFont.display(28, weight: .extraBold))
                        .foregroundStyle(Palette.forest)

                    Text(String(localized: "Voice Banking Studio"))
                        .font(EchoFont.body(14, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 10)

                // Instructions & Teleprompter Card
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "quote.opening")
                            .foregroundStyle(Palette.forest)
                        Text(String(localized: "Say this clearly, close to the phone:"))
                            .font(EchoFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    }

                    Text("\"\(phrase.text)\"")
                        .font(EchoFont.display(24, weight: .bold))
                        .foregroundStyle(Palette.forest)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(Palette.cream, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.forest.opacity(0.12), lineWidth: 1.5))
                }
                .padding(20)
                .background(Palette.surface, in: .rect(cornerRadius: 24))
                .shadow(color: Palette.forest.opacity(0.06), radius: 10, y: 4)
                .padding(.horizontal, 20)

                // Live Audio Waveform Level Meter
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(0..<18, id: \.self) { i in
                            let shape = CGFloat((i % 5) + 3) / 7
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isRecording ? Palette.orange : Palette.forest.opacity(0.2))
                                .frame(width: 8, height: isRecording ? max(8, audioLevel * 48 * shape) : 8)
                        }
                    }
                    .frame(height: 54)

                    if isRecording {
                        Text(String(format: String(localized: "Recording... %.1fs"), recordingTime))
                            .font(EchoFont.body(15, weight: .bold))
                            .foregroundStyle(Palette.orange)
                    } else if recordedURL != nil {
                        if let quality {
                            qualityCard(quality)
                        } else {
                            Text(String(localized: "Recording ready. Play it back, then save."))
                                .font(EchoFont.body(14, weight: .semibold))
                                .foregroundStyle(Palette.forest)
                        }
                    } else {
                        Text(String(localized: "Tap Record when ready"))
                            .font(EchoFont.body(14))
                            .foregroundStyle(Palette.muted)
                    }
                }

                // Action Controls
                VStack(spacing: 14) {
                    if isRecording {
                        Button {
                            stopRecording()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.fill")
                                    .font(.system(size: 20))
                                Text(String(localized: "Stop Recording"))
                                    .font(EchoFont.body(17, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Palette.red, in: .rect(cornerRadius: 18))
                        }
                    } else {
                        HStack(spacing: 14) {
                            // Record Button
                            Button {
                                Task { await startRecording() }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mic.circle.fill")
                                        .font(.system(size: 24))
                                    Text(recordedURL == nil ? String(localized: "Record Voice") : String(localized: "Re-record"))
                                        .font(EchoFont.body(17, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Palette.forest, in: .rect(cornerRadius: 18))
                            }

                            // Play Preview Button
                            if recordedURL != nil {
                                Button {
                                    playPreview()
                                } label: {
                                    Image(systemName: isPlayingPreview ? "stop.fill" : "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(Palette.forest)
                                        .frame(width: 56, height: 56)
                                        .background(Palette.lime, in: .rect(cornerRadius: 18))
                                }
                            }
                        }
                    }

                    if recordedURL != nil && !isRecording {
                        Button {
                            saveRecordingToPhrase()
                        } label: {
                            Text(quality?.isClear == false ? String(localized: "Save Anyway") : String(localized: "Save to Phrase Bank"))
                                .font(EchoFont.body(17, weight: .bold))
                                .foregroundStyle(Palette.forest)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(Palette.lime, in: .rect(cornerRadius: 18))
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(EchoFont.body(14, weight: .semibold))
                            .foregroundStyle(Palette.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                }
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "Record Phrase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(Palette.forest)
                }
            }
            .onDisappear { cleanUpDraft() }
        }
    }

    // MARK: Audio Recording Logic

    private func startRecording() async {
        #if os(iOS)
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = String(localized: "Microphone access is needed to bank this phrase.")
            return
        }

        cleanUpDraft()
        errorMessage = nil
        quality = nil
        qualityMS = nil
        let session = AVAudioSession.sharedInstance()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoVoice_Draft_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            guard audioRecorder?.record() == true else {
                throw CocoaError(.fileWriteUnknown)
            }

            isRecording = true
            recordingTime = 0.0
            recordedURL = url

            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    self.recordingTime += 0.1
                    self.audioRecorder?.updateMeters()
                    let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -60
                    self.audioLevel = CGFloat(max(0, (power + 60) / 60))
                }
            }
        } catch {
            cleanUpDraft()
            errorMessage = String(localized: "Couldn't start recording. Check microphone access and try again.")
        }
        #endif
    }

    private func stopRecording() {
        let duration = audioRecorder?.currentTime ?? recordingTime
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if duration < 0.3 {
            cleanUpDraft()
            errorMessage = String(localized: "That recording was too short. Please record the whole phrase.")
            return
        }
        checkQuality()
    }

    /// Check the take while it can still be redone. See `RecordingQuality`.
    private func checkQuality() {
        guard let url = recordedURL, let file = try? AVAudioFile(forReading: url) else { return }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0]
        else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let startedAt = ProcessInfo.processInfo.systemUptime
        quality = RecordingQuality.analyze(samples: samples, sampleRate: file.processingFormat.sampleRate)
        qualityMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
    }

    private func qualityCard(_ report: RecordingQuality.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if report.isClear {
                    BearMascotView(mood: .proud)
                        .frame(width: 64, height: 64)
                        .padding(.vertical, -10)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.orange)
                        .accessibilityHidden(true)
                }
                Text(report.isClear ? String(localized: "Clear recording") : String(localized: "Worth another take"))
                    .font(EchoFont.body(16, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            ForEach(report.issues, id: \.self) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(EchoFont.body(14, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(issue.advice)
                        .font(EchoFont.body(14))
                        .foregroundStyle(Palette.muted)
                }
            }
            if report.isClear {
                Text(String(localized: "Play it back to be sure, then save. Once your voice changes, this recording can't be made again."))
                    .font(EchoFont.body(14))
                    .foregroundStyle(Palette.muted)
            }
            Text(qualityMetricsLine(report))
                .font(EchoFont.body(12, weight: .semibold))
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder((report.isClear ? Palette.forest : Palette.orange).opacity(0.35), lineWidth: 1.5))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private func qualityMetricsLine(_ report: RecordingQuality.Report) -> String {
        var parts = [String(format: String(localized: "Level %.0f dBFS"), report.speechLevelDB)]
        if report.measuredNoise { parts.append(String(format: String(localized: "%.0f dB above room"), report.snrDB)) }
        parts.append(report.clippedFraction > 0 ? String(format: String(localized: "%.2f%% clipped"), report.clippedFraction * 100) : String(localized: "no clipping"))
        if let qualityMS { parts.append(String(format: String(localized: "checked on this device in %.0f ms"), qualityMS)) }
        return parts.joined(separator: " · ")
    }

    private func playPreview() {
        guard let url = recordedURL else { return }

        if isPlayingPreview {
            audioPlayer?.stop()
            isPlayingPreview = false
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlayingPreview = true

            let duration = audioPlayer?.duration ?? 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.isPlayingPreview = false
            }
        } catch {
            isPlayingPreview = false
            errorMessage = String(localized: "Couldn't play that recording. Please record it again.")
        }
    }

    private func saveRecordingToPhrase() {
        guard let url = recordedURL,
              let data = try? Data(contentsOf: url),
              store.saveBankedRecording(for: phrase, audioData: data)
        else {
            errorMessage = String(localized: "Couldn't save that recording. Your previous recording is unchanged.")
            return
        }
        cleanUpDraft()
        dismiss()
    }

    private func cleanUpDraft() {
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isRecording = false
        isPlayingPreview = false
        if let recordedURL {
            try? FileManager.default.removeItem(at: recordedURL)
            self.recordedURL = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#if canImport(CoreNFC)
// CoreNFC predates strict concurrency and does not mark NFCNDEFReaderSession or
// NFCNDEFTag as Sendable, even though its own callbacks hand them back to you.
// So the completion handlers below still emit "capture of non-Sendable type"
// warnings, which @preconcurrency does not silence — it only relaxes checking at
// the module boundary. Those warnings are accepted rather than worked around:
// CoreNFC serialises these callbacks on the session's own queue, and every
// mutation of this object's state hops to @MainActor explicitly before touching
// anything. Boxing the session in an @unchecked Sendable wrapper would quiet the
// compiler while making the real threading harder to see.
//
// They become hard errors under the Swift 6 language mode. Do not switch this
// target to Swift 6 without first testing NFC on physical hardware.
@preconcurrency import CoreNFC
#endif
import Foundation
import SwiftUI

/// Reads and writes NFC tags so a phrase can be triggered by touching a physical
/// object — a bed rail, a wheelchair tray, a card by the door.
///
/// Why this matters here: tapping a tag needs far less fine motor control than
/// finding one tile on a screen, and the tag can live wherever the person
/// actually needs it. It is also the one part of EchoVoice a visitor can use
/// without being taught the app.
///
/// Each tag stores one external NDEF record carrying the phrase's UUID.
/// EchoVoice reads that record to resolve the exact local phrase. A public URL
/// must not be added until the project has a fallback site it actually controls.
@MainActor
@Observable
final class NFCTagManager: NSObject {
    /// External NDEF type. Must be lowercase per the NFC Forum external-type rules.
    nonisolated private static let externalType = "ayaanrustagi.com:echovoice-phrase"

    enum Outcome: Equatable {
        case idle
        case scanning
        case success(String)
        case failure(String)
    }

    private(set) var outcome: Outcome = .idle

    /// Phrase resolved from the most recent successful read, for the caller to speak.
    private(set) var lastScannedPhraseID: UUID?

    /// Called when a tag resolves to a phrase the app knows about.
    var onPhraseScanned: ((UUID) -> Void)?

    #if canImport(CoreNFC)
    private var readerSession: NFCNDEFReaderSession?
    /// Non-nil only while a write is pending; holds the payload to write on detect.
    private var pendingWriteMessage: NFCNDEFMessage?
    #endif

    /// Whether this device can use NFC at all. iPad and older iPhones cannot.
    var isAvailable: Bool { Self.isSupported }

    /// The Tags tab is shown only where tags can work: a tab that can only
    /// say "not available" is a dead end on every iPad.
    static var isSupported: Bool {
        #if DEBUG
        // Shows the Tags screen in the simulator for demos and screenshots.
        // Writing or scanning still fails there: there is no NFC reader.
        if ProcessInfo.processInfo.arguments.contains("-EchoVoiceShowTags") { return true }
        #endif
        #if ECHOVOICE_NO_NFC
        return false
        #elseif canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    var unavailableReason: String {
        #if ECHOVOICE_NO_NFC
        return String(localized: "NFC is disabled in this development build. Your other communication features are available.")
        #else
        return String(localized: "NFC tag scanning requires a compatible physical iPhone. It isn't available on iPad or in Simulator.")
        #endif
    }

    // MARK: - Scanning

    /// Begin a read session. The caller should already have checked `isAvailable`.
    func beginScanning() {
        #if canImport(CoreNFC)
        guard isAvailable else {
            outcome = .failure(unavailableReason)
            return
        }
        // A session can't be restarted once invalidated — always build a new one.
        readerSession?.invalidate()
        pendingWriteMessage = nil

        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = String(localized: "Hold the top of your iPhone near the tag.")
        readerSession = session
        outcome = .scanning
        session.begin()
        #else
        outcome = .failure(String(localized: "This device doesn't support NFC tags."))
        #endif
    }

    // MARK: - Writing

    /// Begin a write session that programs `phrase` onto the next tag tapped.
    func beginWriting(phrase: Phrase) {
        #if canImport(CoreNFC)
        guard isAvailable else {
            outcome = .failure(unavailableReason)
            return
        }
        guard let message = Self.makeMessage(for: phrase) else {
            outcome = .failure(String(localized: "Couldn't prepare the tag data."))
            return
        }

        readerSession?.invalidate()
        pendingWriteMessage = message

        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = String(localized: "Hold your iPhone near the tag to save “%@”.", defaultValue: "Hold your iPhone near the tag to save \u{201C}\(String(describing: phrase.label))\u{201D}.")
        readerSession = session
        outcome = .scanning
        session.begin()
        #else
        outcome = .failure(String(localized: "This device doesn't support NFC tags."))
        #endif
    }

    #if canImport(CoreNFC)
    /// Build the single-record message described in the type comment.
    nonisolated static func makeMessage(for phrase: Phrase) -> NFCNDEFMessage? {
        guard let typeData = externalType.data(using: .utf8),
              let idData = phrase.id.uuidString.data(using: .utf8)
        else { return nil }

        let phraseRecord = NFCNDEFPayload(
            format: .nfcExternal,
            type: typeData,
            identifier: Data(),
            payload: idData
        )

        return NFCNDEFMessage(records: [phraseRecord])
    }

    /// Pull a phrase UUID out of EchoVoice's namespaced external record.
    nonisolated static func phraseID(from message: NFCNDEFMessage) -> UUID? {
        for record in message.records where record.typeNameFormat == .nfcExternal {
            guard let type = String(data: record.type, encoding: .utf8),
                  type.caseInsensitiveCompare(externalType) == .orderedSame,
                  let raw = String(data: record.payload, encoding: .utf8),
                  let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            else { continue }
            return id
        }

        return nil
    }
    #endif
}

// MARK: - NFCNDEFReaderSessionDelegate

#if canImport(CoreNFC)
extension NFCTagManager: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Nothing to do; `outcome` is already .scanning.
    }

    /// Required by the protocol. Unused: the tag-based callback below is the one
    /// that runs, because it takes precedence when implemented.
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if error != nil {
                session.invalidate(errorMessage: String(localized: "Couldn't connect to that tag. Try again."))
                return
            }

            tag.queryNDEFStatus { status, capacity, statusError in
                guard statusError == nil else {
                    session.invalidate(errorMessage: String(localized: "Couldn't read that tag."))
                    return
                }

                Task { @MainActor in
                    if let message = self.pendingWriteMessage {
                        self.performWrite(message, to: tag, status: status, capacity: capacity, session: session)
                    } else {
                        self.performRead(from: tag, status: status, session: session)
                    }
                }
            }
        }
    }

    private func performRead(
        from tag: any NFCNDEFTag,
        status: NFCNDEFStatus,
        session: NFCNDEFReaderSession
    ) {
        guard status != .notSupported else {
            session.invalidate(errorMessage: String(localized: "That tag isn't NDEF formatted."))
            return
        }

        tag.readNDEF { [weak self] message, _ in
            guard let self else { return }
            guard let message, let id = Self.phraseID(from: message) else {
                session.invalidate(errorMessage: String(localized: "That tag isn't an EchoVoice tag."))
                return
            }
            session.alertMessage = String(localized: "Tag recognized.")
            session.invalidate()

            Task { @MainActor in
                self.lastScannedPhraseID = id
                self.outcome = .success(String(localized: "Tag recognized."))
                self.onPhraseScanned?(id)
            }
        }
    }

    private func performWrite(
        _ message: NFCNDEFMessage,
        to tag: any NFCNDEFTag,
        status: NFCNDEFStatus,
        capacity: Int,
        session: NFCNDEFReaderSession
    ) {
        switch status {
        case .notSupported:
            session.invalidate(errorMessage: String(localized: "That tag can't store EchoVoice data."))
            return
        case .readOnly:
            session.invalidate(errorMessage: String(localized: "That tag is locked and can't be changed."))
            return
        case .readWrite:
            break
        @unknown default:
            session.invalidate(errorMessage: String(localized: "That tag isn't supported."))
            return
        }

        // Refuse rather than let the write fail halfway with a confusing error.
        guard message.length <= capacity else {
            session.invalidate(errorMessage: String(localized: "That tag is too small — it holds %@ bytes but needs %@.", defaultValue: "That tag is too small — it holds \(String(describing: capacity)) bytes but needs \(String(describing: message.length))."))
            return
        }

        tag.writeNDEF(message) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage: String(localized: "Couldn't save to that tag: %@", defaultValue: "Couldn't save to that tag: \(String(describing: error.localizedDescription))"))
                return
            }
            session.alertMessage = String(localized: "Tag saved.")
            session.invalidate()

            Task { @MainActor in
                self.pendingWriteMessage = nil
                self.outcome = .success(String(localized: "Tag saved. Tap it any time to speak this phrase."))
            }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code

        Task { @MainActor in
            self.readerSession = nil
            self.pendingWriteMessage = nil

            switch code {
            case .readerSessionInvalidationErrorUserCanceled,
                 .readerSessionInvalidationErrorFirstNDEFTagRead:
                // Normal termination — never surface these as failures.
                if case .scanning = self.outcome { self.outcome = .idle }
            default:
                // A success path invalidates the session too; don't overwrite it.
                if case .success = self.outcome { return }
                self.outcome = .failure(error.localizedDescription)
            }
        }
    }
}
#endif

# Privacy Policy for EchoVoice

**Last Updated:** August 15, 2026

EchoVoice is private by design for individuals and families affected by speech loss (ALS, MND, stroke, Parkinson's).

## 1. On-Device Operations
EchoVoice processes its features on your device.
- No EchoVoice-operated remote servers
- The app does not upload or synchronize your voice data
- No user accounts or login required
- No internet connection required

Your device's operating-system backup settings may include app data. EchoVoice does not control those backups; review your device backup settings if you do not want its local data backed up.

## 2. Zero Data Collection & Zero Tracking
We collect **zero data**. We do not track users, log usage events, run analytics, or integrate third-party telemetry SDKs of any kind. 

## 3. Audio & Voice Storage
- All phrase audio recordings, message bank files, and speech journal metrics remain strictly within your device's local application container (`FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)`).
- When you use Apple Personal Voice, synthesis runs entirely on-device via Apple's secure SpeechSynthesis APIs (`AVSpeechSynthesizer`).
- Your voice recordings and banked messages are owned entirely by you and your family. You can export a local `.echovoice` backup file via the share sheet anytime.

## 4. Personal Information Phrases
If you choose to enter a name, date of birth, medications, allergies, or an emergency contact, EchoVoice turns those details into phrases in the Personal category. The values are stored in the app's local preferences on your device. EchoVoice does not upload or share them. You can edit or clear them at any time in Settings.

If your emergency contact includes a phone number, the HELP screen can open Apple's Messages app with a help text already written. You send it yourself by tapping Send. EchoVoice never sends a message on its own and cannot read your messages.

## 5. Speech Recognition
When you complete a voice-journal check-in, EchoVoice uses Apple's **on-device** speech recognition (`requiresOnDeviceRecognition = true`) to measure how much of the practice sentence was understood. This runs entirely on your device. Your audio is not sent to Apple, to us, or to anyone else.

## 6. Camera
If you turn on eye tracking, the front TrueDepth camera follows your gaze so you can select phrases without touching the screen. Frames are processed live on-device by ARKit and are never recorded, stored, or transmitted. Eye tracking is off by default and can be turned off at any time in Settings.

## 7. NFC
EchoVoice reads and writes NFC tags that you own. A tag stores a phrase identifier in a namespaced EchoVoice record. It contains no personal information or web URL.

## 8. Medical & Health Disclaimer
EchoVoice is an augmentative and alternative communication (AAC) tool and personal voice journal. It is **NOT** a medical device, and does not diagnose, treat, screen, or monitor any medical condition. Speech-journal measurements are compared only against your own earlier readings, never against a population norm. Review them with a licensed Speech-Language Pathologist.

## 9. Children
EchoVoice does not knowingly collect data from anyone, including children. It collects no data from any user.

## 10. Contact Information
For questions regarding EchoVoice's privacy commitment, email: **ayaan.rustagi2010@gmail.com**

---

**Last reviewed against the shipping build:** the app requests exactly four permissions — microphone, speech recognition, camera, and NFC — and every one is described above. If a future build adds a permission, add it here in the same commit.

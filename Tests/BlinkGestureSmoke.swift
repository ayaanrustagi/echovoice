import Foundation

/// HELP-by-blink must be dependable when meant and impossible when not.
@main
enum BlinkGestureSmoke {
    static let frame = 1.0 / 60.0

    static func main() {
        ordinaryBlinkingNeverCallsHelp()
        aBurstOfBlinksAloneOnlyArms()
        fiveQuickBlinksThenAHoldCallsHelp()
        aHoldStartedJustBeforeTimeoutStillConfirms()
        armingExpiresWithoutAHold()
        aShortHoldWhileArmedCancelsWithoutTurningThePage()
        oneRetryAfterAShortHold()
        flutterDuringTheHoldStillConfirms()
        heavyLidsWhileLookingDownDoNothing()
        deliberateHoldTurnsThePageWhenEnabled()
        thresholdFlickerIsNotABlink()
        losingTheFaceResetsEverything()
        print("Blink gesture smoke tests passed")
    }

    /// Run the detector over a scripted eyelid trace.
    struct Script {
        var detector = BlinkGestureDetector()
        var time = 0.0
        var events: [BlinkGestureDetector.Event] = []

        mutating func open(_ seconds: Double, level: Double = 0.05) { run(seconds, level) }
        mutating func closed(_ seconds: Double, level: Double = 0.95) { run(seconds, level) }

        mutating func blink(closedFor seconds: Double = 0.15, thenOpen gap: Double = 0.25) {
            closed(seconds)
            open(gap)
        }

        mutating func run(_ seconds: Double, _ level: Double, right: Double? = nil) {
            for _ in 0..<Int((seconds / frame).rounded()) {
                time += frame
                events += detector.update(left: level, right: right ?? level, time: time)
            }
        }

        var helpCalls: Int { events.filter { $0 == .helpConfirmed }.count }
        var pageTurns: Int { events.filter { $0 == .pageTurn }.count }
        var armings: Int { events.filter { $0 == .helpArmed }.count }
    }

    static func ordinaryBlinkingNeverCallsHelp() {
        var s = Script()
        // Ten minutes of natural blinking: ~17 a minute, irregular spacing,
        // durations 100–300ms, including occasional double blinks.
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let end = 600.0
        while s.time < end {
            s.open(1.5 + random() * 4.0)
            s.blink(closedFor: 0.1 + random() * 0.2, thenOpen: 0.3)
            if random() < 0.1 { s.blink(closedFor: 0.12, thenOpen: 0.3) }
        }
        precondition(s.helpCalls == 0, "natural blinking must never call HELP")
        precondition(s.armings == 0, "natural blinking should not even arm HELP")
        precondition(s.pageTurns == 0, "natural blinking must not turn pages")
    }

    static func aBurstOfBlinksAloneOnlyArms() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        s.open(6)
        precondition(s.armings == 1 && s.helpCalls == 0, "arming without the held closure must not call HELP")
    }

    static func fiveQuickBlinksThenAHoldCallsHelp() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        precondition(s.detector.isArmed)
        s.open(0.5)
        s.closed(2.0)
        precondition(s.helpCalls == 1, "the full gesture must call HELP exactly once")
        s.open(1)
        precondition(s.helpCalls == 1 && s.pageTurns == 0, "reopening after HELP does nothing more")
    }

    /// The old detector disarmed on a fixed timer, so someone who started the
    /// confirming hold late lost it midway and turned the page instead.
    static func aHoldStartedJustBeforeTimeoutStillConfirms() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        s.open(3.6)                    // armed ~3.6s ago, window is 4s
        s.closed(2.0)                  // hold straddles the 4s mark
        precondition(s.helpCalls == 1, "a hold that began inside the window must be allowed to finish")
        precondition(s.pageTurns == 0)
    }

    static func armingExpiresWithoutAHold() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        s.open(4.5)
        precondition(!s.detector.isArmed && s.events.contains(.helpCancelled))
        s.closed(2.0)
        s.open(0.5)
        precondition(s.helpCalls == 0, "a hold after the window has closed must not call HELP")
    }

    /// A hold that stops short never turns the page; a second one disarms.
    static func aShortHoldWhileArmedCancelsWithoutTurningThePage() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        s.closed(1.2)
        s.open(0.5)
        precondition(s.helpCalls == 0 && s.pageTurns == 0 && s.detector.isArmed, "one short hold keeps HELP ready for a retry")
        s.closed(1.2)
        s.open(0.5)
        precondition(s.helpCalls == 0 && s.pageTurns == 0 && !s.detector.isArmed, "a second short hold disarms")
    }

    static func oneRetryAfterAShortHold() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        s.closed(1.2)
        s.open(1.0)
        s.closed(2.0)
        precondition(s.helpCalls == 1, "someone who opened too early can hold again")
    }

    /// Eyelid values flicker. One open-looking frame in the middle of a
    /// deliberate hold must not end it.
    static func flutterDuringTheHoldStillConfirms() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        s.open(0.4)
        s.closed(1.0)
        s.run(frame, 0.3)
        s.closed(1.0)
        precondition(s.helpCalls == 1, "a one-frame flutter aborted the HELP hold")
    }

    static func heavyLidsWhileLookingDownDoNothing() {
        var s = Script()
        s.open(1)
        // Lids sag to ~0.65 while reading the bottom row for three seconds.
        s.closed(3, level: 0.65)
        s.open(1)
        precondition(s.pageTurns == 0 && s.helpCalls == 0, "heavy lids are not a deliberate closure")
    }

    static func deliberateHoldTurnsThePageWhenEnabled() {
        var s = Script()
        s.open(1)
        s.closed(1.2)
        s.open(0.5)
        precondition(s.pageTurns == 1)

        var off = Script()
        off.detector.pageTurnEnabled = false
        off.open(1)
        off.closed(1.2)
        off.open(0.5)
        precondition(off.pageTurns == 0, "page turning can be switched off")
    }

    static func thresholdFlickerIsNotABlink() {
        var s = Script()
        s.open(0.5)
        // Values bouncing either side of the 0.6 close threshold but never
        // below the 0.45 open threshold: one closure, not a stream of blinks.
        for i in 0..<120 {
            s.run(frame, i.isMultiple(of: 2) ? 0.62 : 0.55)
        }
        s.open(0.5)
        let quickBlinks = s.events.filter { if case .quickBlink = $0 { return true } else { return false } }
        precondition(quickBlinks.count <= 1, "flicker produced \(quickBlinks.count) blinks")
    }

    static func losingTheFaceResetsEverything() {
        var s = Script()
        s.open(1)
        for _ in 0..<5 { s.blink() }
        precondition(s.detector.isArmed)
        s.detector.faceLost()
        precondition(!s.detector.isArmed && s.detector.quickBlinkCount == 0)
        s.closed(2)
        s.open(0.5)
        precondition(s.helpCalls == 0, "an arming from before the face was lost must not survive")
    }
}

import Foundation

/// Blink gestures, as a pure state machine with injected time.
///
/// Two gestures exist:
///
/// * **HELP** — five quick blinks within 3.5 s *arm* HELP. Arming alone does
///   nothing; a deliberate closure held for `helpHold` while armed confirms
///   it. Ordinary blinking (15–20 a minute, rarely five in a burst) cannot
///   produce that sequence, and even a burst still needs the held closure.
/// * **Page turn** — a deliberate closure of at least `pageHold` while not
///   armed. Can be switched off in Settings for people whose lids droop.
///
/// "Deliberate" means the lids were genuinely shut, not heavy: the average
/// closure over the hold must reach `deliberateLevel`. Lids that sag while
/// someone reads the bottom row of the board sit well below full closure,
/// so looking down does not turn the page or confirm HELP.
struct BlinkGestureDetector: Sendable {
    struct Configuration: Sendable {
        /// Both eyes above this counts as closed…
        var closeThreshold = 0.6
        /// …and either eye below this counts as open again. The gap stops a
        /// value hovering at the threshold from producing a stream of blinks.
        var openThreshold = 0.45
        var quickBlinkMinimum: TimeInterval = 0.08
        var quickBlinkMaximum: TimeInterval = 0.45
        /// Closure edges closer than this are one blink seen twice.
        var quickBlinkSpacing: TimeInterval = 0.24
        var sequenceWindow: TimeInterval = 3.5
        var blinksToArm = 5
        /// How long HELP stays armed waiting for the confirming hold to *start*.
        var armedWindow: TimeInterval = 4.0
        var helpHold: TimeInterval = 1.8
        var pageHold: TimeInterval = 1.0
        var deliberateLevel = 0.7
        /// The eyes must look open this long before a closure counts as
        /// over. Lid values flicker; one open-looking frame in the middle of
        /// a deliberate hold must not end it.
        var openDebounce: TimeInterval = 0.1
    }

    enum Event: Equatable, Sendable {
        case quickBlink(count: Int)
        case helpArmed
        case helpConfirmed
        case helpCancelled
        /// A hold while armed ended too soon; HELP stays ready for one retry.
        case helpHoldTooShort
        case pageTurn
    }

    var configuration = Configuration()
    /// When false, a held closure never turns the page.
    var pageTurnEnabled = true

    private(set) var isClosed = false
    private(set) var isArmed = false
    private(set) var quickBlinkCount = 0

    private var closedAt: TimeInterval?
    private var openSince: TimeInterval?
    /// Each arming allows one retry of a hold that stopped short.
    private var retriedHold = false
    private var closureSum = 0.0
    private var closureFrames = 0
    private var holdConsumed = false
    private var armedUntil: TimeInterval = 0
    private var blinkTimes: [TimeInterval] = []
    private var lastQuickBlinkAt: TimeInterval?

    init(configuration: Configuration = Configuration(), pageTurnEnabled: Bool = true) {
        self.configuration = configuration
        self.pageTurnEnabled = pageTurnEnabled
    }

    /// How long the eyes have been shut, or 0 when open.
    func closedDuration(at time: TimeInterval) -> TimeInterval {
        guard isClosed, let closedAt else { return 0 }
        return max(0, time - closedAt)
    }

    /// Progress toward confirming HELP, 0...1, for on-screen feedback.
    func helpHoldProgress(at time: TimeInterval) -> Double {
        guard isArmed, isClosed else { return 0 }
        return min(closedDuration(at: time) / configuration.helpHold, 1)
    }

    mutating func update(left: Double, right: Double, time: TimeInterval) -> [Event] {
        var events: [Event] = []

        // An armed sequence expires if no confirming hold has *started* in
        // time. A hold already under way may finish — otherwise someone slow
        // to react would have HELP disarm in the middle of confirming it.
        if isArmed, !isClosed, time > armedUntil {
            isArmed = false
            events.append(.helpCancelled)
        }

        let bothClosed = left > configuration.closeThreshold && right > configuration.closeThreshold
        let eitherOpen = left < configuration.openThreshold || right < configuration.openThreshold

        if !isClosed && bothClosed {
            isClosed = true
            closedAt = time
            openSince = nil
            closureSum = 0
            closureFrames = 0
            holdConsumed = false
        }

        if isClosed, let closedAt {
            if eitherOpen {
                if openSince == nil { openSince = time }
            } else {
                openSince = nil
                closureSum += min(left, right)
                closureFrames += 1
                if isArmed, !holdConsumed, time - closedAt >= configuration.helpHold, isDeliberate {
                    holdConsumed = true
                    isArmed = false
                    events.append(.helpConfirmed)
                }
            }

            // The closure ended when the eyes first opened, once they have
            // stayed open long enough to be believed.
            if let opened = openSince, time - opened >= configuration.openDebounce {
                let duration = opened - closedAt
                isClosed = false
                self.closedAt = nil
                openSince = nil
                events.append(contentsOf: finishClosure(duration: duration, at: opened))
            }
        }

        return events
    }

    /// The face left the camera's view. Nothing measured before counts.
    mutating func faceLost() {
        isClosed = false
        closedAt = nil
        openSince = nil
        isArmed = false
        holdConsumed = false
        blinkTimes.removeAll()
        quickBlinkCount = 0
        lastQuickBlinkAt = nil
    }

    // MARK: Internals

    private var isDeliberate: Bool {
        closureFrames > 0 && closureSum / Double(closureFrames) >= configuration.deliberateLevel
    }

    private mutating func finishClosure(duration: TimeInterval, at time: TimeInterval) -> [Event] {
        if holdConsumed { return [] }

        if duration >= configuration.pageHold && isDeliberate {
            if isArmed {
                // Held, but not long enough to confirm. Never turn the page
                // someone was not trying to turn. Allow one retry — the
                // person may simply have opened too early — then disarm.
                blinkTimes.removeAll()
                quickBlinkCount = 0
                if !retriedHold {
                    retriedHold = true
                    armedUntil = time + configuration.armedWindow
                    return [.helpHoldTooShort]
                }
                isArmed = false
                return [.helpCancelled]
            }
            blinkTimes.removeAll()
            quickBlinkCount = 0
            return pageTurnEnabled ? [.pageTurn] : []
        }

        guard !isArmed,
              duration >= configuration.quickBlinkMinimum,
              duration <= configuration.quickBlinkMaximum else { return [] }

        if let last = lastQuickBlinkAt, time - last < configuration.quickBlinkSpacing { return [] }
        lastQuickBlinkAt = time
        blinkTimes.append(time)
        blinkTimes.removeAll { time - $0 > configuration.sequenceWindow }
        quickBlinkCount = blinkTimes.count

        guard blinkTimes.count >= configuration.blinksToArm else {
            return [.quickBlink(count: quickBlinkCount)]
        }
        blinkTimes.removeAll()
        quickBlinkCount = 0
        isArmed = true
        retriedHold = false
        armedUntil = time + configuration.armedWindow
        return [.quickBlink(count: configuration.blinksToArm), .helpArmed]
    }
}

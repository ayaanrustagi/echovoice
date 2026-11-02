import CoreGraphics
import Foundation

/// A control that dwell can select.
struct DwellTarget: Equatable, Sendable {
    enum Kind: String, Sendable {
        case standard
        /// HELP and anything like it. Needs a longer, strictly-inside dwell so
        /// a cursor drifting across the bottom of the screen cannot call it.
        case emergency
    }

    let id: String
    let frame: CGRect
    var kind: Kind = .standard
}

/// What the tracker can say about the cursor on a given frame.
enum GazeTrackingState: Equatable, Sendable {
    /// A fresh, open-eyed sample.
    case tracking
    /// Eyes closed or closing: the position is unreliable, so dwell pauses.
    case eyesClosed
    /// No face, or no fresh sample.
    case lost
}

/// Target-aware dwell selection, as a pure state machine.
///
/// The rules exist to stop the two failures that make people abandon
/// hands-free access — selecting the wrong thing, and never managing to
/// select the right one:
///
/// * **Snapping.** A cursor just outside a target (within `snapMargin`)
///   acquires it. Gaze jitter of a few dozen points then stops meaning a miss.
///   Not when it is about as close to another control (`ambiguityMargin`):
///   halfway across a gutter, picking the nearer tile is a coin flip.
/// * **Hysteresis.** Once a target is acquired it is kept until the cursor is
///   clearly elsewhere: inside another target for `switchDelay`, or beyond
///   `exitMargin` for `exitGrace`. A brief wobble pauses progress instead of
///   restarting it.
/// * **Pausing, not resetting, on blinks and short tracking gaps.** A blink
///   mid-dwell costs nothing; only a sustained loss (`lossGrace`) resets.
/// * **One selection per visit.** A completed target is latched until the
///   cursor leaves it, so holding still on a phrase never repeats it — even
///   if a sheet or alert covered it in between.
/// * **Settling after a selection.** Nothing new starts for `cooldown`, so a
///   page that changes under the cursor cannot select its new contents.
/// * **A fresh visit after a screen change.** After `reset`, whatever is
///   under the resting cursor was not chosen; it must be left and returned to.
///   This lasts until the cursor moves, not for a fixed time: a screen that
///   slides in can register its controls a second or more later.
/// * **Safer emergency targets.** No snapping, and a longer dwell.
struct DwellSelector: Sendable {
    struct Configuration: Sendable {
        var snapMargin: CGFloat = 22
        /// A snap needs the nearest target to be this much nearer than the next.
        var ambiguityMargin: CGFloat = 8
        var exitMargin: CGFloat = 30
        var acquireDelay: TimeInterval = 0.12
        var switchDelay: TimeInterval = 0.18
        var exitGrace: TimeInterval = 0.30
        var lossGrace: TimeInterval = 0.50
        /// Eyes shut longer than a blink: progress is dropped, not paused.
        var closedGrace: TimeInterval = 0.60
        var cooldown: TimeInterval = 0.60
        var emergencyMultiplier: Double = 2.0
        var emergencyMinimum: TimeInterval = 2.5
    }

    var configuration = Configuration()

    private(set) var hoveredID: String?
    private(set) var progress: Double = 0
    /// Set when the last update completed a selection.
    private(set) var lastSelectedID: String?

    private var accumulated: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var candidateID: String?
    private var candidateSince: TimeInterval = 0
    private var awaySince: TimeInterval?
    private var lostSince: TimeInterval?
    /// A target that may not fire until the cursor leaves it.
    private struct Latch {
        /// Where the target last was, so a latch survives it being covered
        /// or removed until the cursor really moves away from that spot.
        var frame: CGRect
        /// Leaving has to last `exitGrace`: one frame of jitter is not leaving.
        var awaySince: TimeInterval?
    }
    private var latched: [String: Latch] = [:]
    private var closedSince: TimeInterval?
    /// Where the cursor rested after a reset or a selection. Until it moves
    /// away, anything that turns up there — including controls that register
    /// late — is latched rather than dwelled on. Only targets there are
    /// latched, not whatever the person looks at next.
    private var settleAnchor: CGPoint?
    private var anchorAwaySince: TimeInterval?
    private var needsSettleAnchor = false
    private var cooldownUntil: TimeInterval = -.infinity

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// The dwell a target needs, given the person's chosen dwell time.
    func requiredDwell(for kind: DwellTarget.Kind, base: TimeInterval) -> TimeInterval {
        let base = max(0.3, base)
        switch kind {
        case .standard: return base
        case .emergency: return max(configuration.emergencyMinimum, base * configuration.emergencyMultiplier)
        }
    }

    /// Advance one frame. Returns the id of a target selected on this frame.
    @discardableResult
    mutating func update(
        cursor: CGPoint?,
        state: GazeTrackingState,
        targets: [DwellTarget],
        time: TimeInterval,
        dwellDuration: TimeInterval
    ) -> String? {
        lastSelectedID = nil
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time

        // A hovered target that has vanished (page change, sheet, disabled)
        // cannot keep collecting dwell.
        if let hoveredID, !targets.contains(where: { $0.id == hoveredID }) {
            clearHover()
        }

        guard state != .lost, let cursor else {
            let since = lostSince ?? time
            lostSince = since
            if time - since >= configuration.lossGrace {
                clearHover()
                candidateID = nil
            }
            return nil
        }
        lostSince = nil

        // Closed eyes: hold everything where it is for a blink; a longer
        // closure is a rest, not a pause, and drops the progress.
        guard state == .tracking else {
            let since = closedSince ?? time
            closedSince = since
            if time - since >= configuration.closedGrace {
                clearHover()
                candidateID = nil
            }
            return nil
        }
        closedSince = nil

        if needsSettleAnchor {
            needsSettleAnchor = false
            settleAnchor = cursor
            anchorAwaySince = nil
        }
        releaseAnchorIfLeft(cursor: cursor, time: time)
        releaseLatchesLeft(cursor: cursor, targets: targets, time: time)
        let pick = bestTarget(at: cursor, in: targets)
        if let pick, latched[pick.id] == nil,
           let anchor = settleAnchor, distance(from: anchor, to: pick.frame) <= exitMargin(for: pick) {
            latched[pick.id] = Latch(frame: pick.frame)
        }

        if let hovered = hoveredID, let hoveredTarget = targets.first(where: { $0.id == hovered }) {
            let stillNear = distance(from: cursor, to: hoveredTarget.frame) <= exitMargin(for: hoveredTarget)
            let pickedOther = pick.map { $0.id != hovered } ?? false
            // Another target only takes over when the cursor is actually on it,
            // not merely within snapping distance.
            let insideOther = pickedOther && (pick?.frame.contains(cursor) ?? false)

            if !insideOther && (stillNear || pick?.id == hovered) {
                awaySince = nil
                candidateID = nil
                return accumulate(on: hoveredTarget, dt: dt, time: time, dwellDuration: dwellDuration)
            }

            let away = awaySince ?? time
            awaySince = away
            if let other = pick, other.id != hovered {
                if stabilized(other.id, time: time, delay: configuration.switchDelay) {
                    acquire(other.id)
                }
            } else if time - away >= configuration.exitGrace {
                clearHover()
            }
            return nil
        }

        guard let pick else {
            candidateID = nil
            return nil
        }
        if stabilized(pick.id, time: time, delay: configuration.acquireDelay) {
            acquire(pick.id)
        }
        return nil
    }

    /// An outside watchdog saw tracking stop for longer than `lossGrace`
    /// (frames stop arriving altogether, so `update` is not being called).
    /// Progress is dropped; the latch is kept, so looking back at a phrase
    /// that was just spoken does not speak it again.
    mutating func trackingLost() {
        clearHover()
        candidateID = nil
    }

    /// Forget everything, including the latch. Use when the screen changes
    /// wholesale (a new tab, a sheet, a mode switch).
    mutating func reset(time: TimeInterval? = nil) {
        clearHover()
        candidateID = nil
        latched.removeAll()
        lostSince = nil
        closedSince = nil
        lastTime = nil
        settleAnchor = nil
        needsSettleAnchor = true
        if let time {
            cooldownUntil = time + configuration.cooldown
        }
    }

    // MARK: Internals

    private mutating func accumulate(on target: DwellTarget, dt: TimeInterval, time: TimeInterval, dwellDuration: TimeInterval) -> String? {
        guard latched[target.id] == nil, time >= cooldownUntil else {
            accumulated = 0
            progress = 0
            return nil
        }
        accumulated += dt
        let required = requiredDwell(for: target.kind, base: dwellDuration)
        progress = min(accumulated / required, 1)
        guard accumulated >= required else { return nil }

        latched[target.id] = Latch(frame: target.frame)
        cooldownUntil = time + configuration.cooldown
        settleAnchor = nil
        needsSettleAnchor = true
        accumulated = 0
        progress = 0
        lastSelectedID = target.id
        return target.id
    }

    private mutating func acquire(_ id: String) {
        hoveredID = id
        accumulated = 0
        progress = 0
        awaySince = nil
        candidateID = nil
    }

    private mutating func clearHover() {
        hoveredID = nil
        accumulated = 0
        progress = 0
        awaySince = nil
    }

    private mutating func stabilized(_ id: String, time: TimeInterval, delay: TimeInterval) -> Bool {
        if candidateID != id {
            candidateID = id
            candidateSince = time
        }
        return time - candidateSince >= delay
    }

    /// Leaving the resting point has to last `exitGrace`, like leaving a
    /// latched target: tremor is not a decision to look elsewhere.
    private mutating func releaseAnchorIfLeft(cursor: CGPoint, time: TimeInterval) {
        guard let anchor = settleAnchor else { return }
        guard hypot(cursor.x - anchor.x, cursor.y - anchor.y) > configuration.exitMargin else {
            anchorAwaySince = nil
            return
        }
        let away = anchorAwaySince ?? time
        anchorAwaySince = away
        if time - away >= configuration.exitGrace {
            settleAnchor = nil
            anchorAwaySince = nil
        }
    }

    private mutating func releaseLatchesLeft(cursor: CGPoint, targets: [DwellTarget], time: TimeInterval) {
        guard !latched.isEmpty else { return }
        for (id, latch) in latched {
            // A covered or removed target keeps its latch at its last position:
            // its reappearance under a cursor that never left is not a new visit.
            let current = targets.first(where: { $0.id == id })
            let frame = current?.frame ?? latch.frame
            let margin = current.map(exitMargin(for:)) ?? configuration.exitMargin
            if distance(from: cursor, to: frame) > margin {
                let away = latch.awaySince ?? time
                if time - away >= configuration.exitGrace {
                    latched[id] = nil
                } else {
                    latched[id] = Latch(frame: frame, awaySince: away)
                }
            } else {
                latched[id] = Latch(frame: frame, awaySince: nil)
            }
        }
    }

    /// The target under the cursor, or failing that the nearest one within
    /// snapping distance. When several contain the cursor (a control drawn over
    /// a tile), the smallest wins: it is the more specific thing being aimed at.
    private func bestTarget(at cursor: CGPoint, in targets: [DwellTarget]) -> DwellTarget? {
        let containing = targets.filter { $0.frame.contains(cursor) }
        if let smallest = containing.min(by: { area($0.frame) < area($1.frame) }) {
            return smallest
        }
        // Every nearby control counts towards ambiguity, HELP included, but
        // only a standard one can be snapped to.
        let nearby = targets
            .map { ($0, distance(from: cursor, to: $0.frame)) }
            .filter { $0.1 <= configuration.snapMargin + configuration.ambiguityMargin }
            .sorted { $0.1 < $1.1 }
        guard let nearest = nearby.first,
              nearest.0.kind == .standard,
              nearest.1 <= configuration.snapMargin else { return nil }
        if nearby.count > 1, nearby[1].1 - nearest.1 < configuration.ambiguityMargin {
            return nil
        }
        return nearest.0
    }

    private func exitMargin(for target: DwellTarget) -> CGFloat {
        target.kind == .emergency ? 0 : configuration.exitMargin
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

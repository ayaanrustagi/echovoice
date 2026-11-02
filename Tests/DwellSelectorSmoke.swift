import CoreGraphics
import Foundation

/// Selection safety for dwell: the wrong thing is not selected, the right
/// thing is not lost to jitter or blinks, nothing repeats, and HELP is hard to
/// hit by accident.
@main
enum DwellSelectorSmoke {
    static let frame = 1.0 / 60.0
    static let dwell = 1.0

    // Two board tiles side by side with a 20pt gutter, and HELP below them.
    static let left = DwellTarget(id: "left", frame: CGRect(x: 16, y: 200, width: 170, height: 140))
    static let right = DwellTarget(id: "right", frame: CGRect(x: 206, y: 200, width: 170, height: 140))
    static let help = DwellTarget(id: "help", frame: CGRect(x: 16, y: 700, width: 170, height: 60), kind: .emergency)
    static let targets = [left, right, help]

    static func main() {
        selectsAfterTheDwell()
        selectsOncePerVisit()
        ignoresWhatIsNotUnderTheCursor()
        snapsToANearMiss()
        keepsTargetThroughBriefWobble()
        switchesToANeighbourOnlyWhenHeldThere()
        pausesDuringBlinks()
        resetsAfterSustainedTrackingLoss()
        shortTrackingGapsOnlyPause()
        emergencyNeedsLongerStrictDwell()
        settlesAfterASelection()
        forgetsVanishedTargets()
        screenChangeNeedsAFreshVisit()
        coveredTargetStaysLatched()
        lateRegisteringTargetStillNeedsAFreshVisit()
        aJitterSpikeDoesNotReleaseTheLatch()
        aTargetLookedAtRightAfterASelectionStillWorks()
        aLongEyeClosureDropsProgress()
        aSlowScreenTransitionStillNeedsAFreshVisit()
        restingInTheGutterAfterAScreenChangeSelectsNothing()
        movingAwayEndsTheRestingRule()
        aCursorBetweenTwoTargetsSelectsNeither()
        aCursorBesideHelpDoesNotSnapToItsNeighbour()
        aClearNearMissInTheGutterStillSnaps()
        print("Dwell selector smoke tests passed")
    }

    /// Feed the same cursor for `seconds`, returning every selection made.
    @discardableResult
    static func hold(
        _ selector: inout DwellSelector,
        at point: CGPoint?,
        for seconds: Double,
        from start: inout Double,
        state: GazeTrackingState = .tracking,
        targets: [DwellTarget] = targets,
        dwell: Double = dwell
    ) -> [String] {
        var fired: [String] = []
        let steps = Int((seconds / frame).rounded())
        for _ in 0..<steps {
            start += frame
            if let id = selector.update(cursor: point, state: state, targets: targets, time: start, dwellDuration: dwell) {
                fired.append(id)
            }
        }
        return fired
    }

    static let leftCenter = CGPoint(x: 101, y: 270)
    static let rightCenter = CGPoint(x: 291, y: 270)

    static func selectsAfterTheDwell() {
        var s = DwellSelector()
        var t = 0.0
        precondition(hold(&s, at: leftCenter, for: 0.9, from: &t).isEmpty, "must not fire before the dwell completes")
        precondition(s.hoveredID == "left" && s.progress > 0.5)
        precondition(hold(&s, at: leftCenter, for: 0.3, from: &t) == ["left"])
    }

    static func selectsOncePerVisit() {
        var s = DwellSelector()
        var t = 0.0
        // Resting on one phrase for ten seconds speaks it once, not six times.
        precondition(hold(&s, at: leftCenter, for: 10, from: &t) == ["left"])
        // Leaving and coming back is a new visit.
        hold(&s, at: CGPoint(x: 196, y: 500), for: 0.6, from: &t)
        precondition(hold(&s, at: leftCenter, for: 1.5, from: &t) == ["left"])
    }

    static func ignoresWhatIsNotUnderTheCursor() {
        var s = DwellSelector()
        var t = 0.0
        precondition(hold(&s, at: CGPoint(x: 196, y: 500), for: 5, from: &t).isEmpty)
        precondition(s.hoveredID == nil)
    }

    static func snapsToANearMiss() {
        var s = DwellSelector()
        var t = 0.0
        // 12pt outside the left tile, in empty space: jitter, not a miss.
        precondition(hold(&s, at: CGPoint(x: 101, y: 352), for: 1.5, from: &t) == ["left"])
    }

    static func keepsTargetThroughBriefWobble() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.5, from: &t)
        let before = s.progress
        // A 0.2s excursion to empty space beyond the exit margin pauses progress.
        hold(&s, at: CGPoint(x: 101, y: 420), for: 0.2, from: &t)
        precondition(s.hoveredID == "left" && abs(s.progress - before) < 1e-9, "wobble must pause, not reset")
        precondition(hold(&s, at: leftCenter, for: 0.75, from: &t) == ["left"], "remaining dwell completes the selection")
    }

    static func switchesToANeighbourOnlyWhenHeldThere() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.6, from: &t)
        // A brief pass through the neighbour does not steal the target.
        hold(&s, at: rightCenter, for: 0.1, from: &t)
        precondition(s.hoveredID == "left")
        // Holding on the neighbour does, and it starts from zero.
        hold(&s, at: rightCenter, for: 0.25, from: &t)
        precondition(s.hoveredID == "right" && s.progress < 0.3, "neighbour takes over with fresh progress")
        let fired = hold(&s, at: rightCenter, for: 1.1, from: &t)
        precondition(fired == ["right"], "only the neighbour fires, got \(fired)")
    }

    static func pausesDuringBlinks() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.5, from: &t)
        let before = s.progress
        // Eyes shut for 0.4s, with a garbage cursor position as lids close.
        let fired = hold(&s, at: rightCenter, for: 0.4, from: &t, state: .eyesClosed)
        precondition(fired.isEmpty && s.hoveredID == "left" && abs(s.progress - before) < 1e-9, "blink must freeze dwell")
        precondition(hold(&s, at: leftCenter, for: 0.75, from: &t) == ["left"])
    }

    static func resetsAfterSustainedTrackingLoss() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.8, from: &t)
        precondition(hold(&s, at: nil, for: 0.8, from: &t, state: .lost).isEmpty)
        precondition(s.hoveredID == nil && s.progress == 0, "lost face must reset dwell")
        // Coming back must re-earn the whole dwell (plus acquisition).
        precondition(hold(&s, at: leftCenter, for: 0.9, from: &t).isEmpty, "no selection from stale progress")
    }

    static func shortTrackingGapsOnlyPause() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.6, from: &t)
        hold(&s, at: nil, for: 0.2, from: &t, state: .lost)
        precondition(s.hoveredID == "left", "a dropped frame or two is not a lost face")
        precondition(hold(&s, at: leftCenter, for: 0.6, from: &t) == ["left"])
    }

    static func emergencyNeedsLongerStrictDwell() {
        var s = DwellSelector()
        precondition(s.requiredDwell(for: .emergency, base: 1.0) == 2.5)
        precondition(s.requiredDwell(for: .emergency, base: 2.0) == 4.0)
        var t = 0.0
        // Near HELP but outside it: no snapping onto an emergency target.
        precondition(hold(&s, at: CGPoint(x: 101, y: 770), for: 5, from: &t).isEmpty)
        // Inside for the ordinary dwell: not enough.
        precondition(hold(&s, at: CGPoint(x: 101, y: 730), for: 1.5, from: &t).isEmpty)
        // Stepping outside HELP, even slightly, loses it.
        hold(&s, at: CGPoint(x: 101, y: 765), for: 0.5, from: &t)
        precondition(s.hoveredID == nil, "HELP must not be held from outside")
        // A full, deliberate dwell does call it.
        precondition(hold(&s, at: CGPoint(x: 101, y: 730), for: 2.8, from: &t) == ["help"])
    }

    static func settlesAfterASelection() {
        var s = DwellSelector()
        var t = 0.0
        precondition(hold(&s, at: leftCenter, for: 1.2, from: &t) == ["left"])
        // The page changes under the cursor: a new target appears where it rests.
        let newPage = [DwellTarget(id: "next-page-tile", frame: left.frame), right, help]
        let fired = hold(&s, at: leftCenter, for: 4, from: &t, targets: newPage)
        precondition(fired.isEmpty, "a tile that appears under a resting cursor was not chosen and must not fire")
        hold(&s, at: CGPoint(x: 101, y: 500), for: 0.4, from: &t, targets: newPage)
        precondition(hold(&s, at: leftCenter, for: 1.4, from: &t, targets: newPage) == ["next-page-tile"],
                     "looking away and back selects it normally")
    }

    /// After a screen change (a sheet closing, a page turned by blink), the
    /// thing that happens to be under a resting cursor was not chosen. It
    /// must be looked away from and back to before it can fire.
    static func screenChangeNeedsAFreshVisit() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.3, from: &t)
        s.reset(time: t)
        precondition(hold(&s, at: leftCenter, for: 5, from: &t).isEmpty, "resting through a screen change must not select")
        hold(&s, at: CGPoint(x: 101, y: 500), for: 0.4, from: &t)
        precondition(hold(&s, at: leftCenter, for: 1.4, from: &t) == ["left"], "a deliberate return selects normally")
    }

    /// The reported case: HELP's alert covered the board, Stop was chosen,
    /// and "I'm Okay" — still under the cursor when the board came back —
    /// was spoken again. A latched target that is covered stays latched until
    /// the cursor actually leaves where it was.
    static func coveredTargetStaysLatched() {
        var s = DwellSelector()
        var t = 0.0
        precondition(hold(&s, at: leftCenter, for: 1.3, from: &t) == ["left"])
        hold(&s, at: leftCenter, for: 2, from: &t, targets: [help])   // covered
        precondition(hold(&s, at: leftCenter, for: 4, from: &t).isEmpty, "a phrase must not repeat after its cover closes")
    }

    /// After a cover closes, the board's controls register again a frame or
    /// two later. One that appears under the resting cursor while settling
    /// is treated the same as one that was already there.
    static func lateRegisteringTargetStillNeedsAFreshVisit() {
        var s = DwellSelector()
        var t = 0.0
        s.reset(time: t)
        hold(&s, at: leftCenter, for: 0.1, from: &t, targets: [])        // nothing registered yet
        precondition(hold(&s, at: leftCenter, for: 5, from: &t).isEmpty, "a control that appears under the cursor was not chosen")
        hold(&s, at: CGPoint(x: 101, y: 500), for: 0.4, from: &t)
        precondition(hold(&s, at: leftCenter, for: 1.4, from: &t) == ["left"])
    }

    /// One frame of jitter beyond the exit margin is not leaving.
    static func aJitterSpikeDoesNotReleaseTheLatch() {
        var s = DwellSelector()
        var t = 0.0
        let nearEdge = CGPoint(x: 101, y: 335)            // 5pt inside the bottom edge
        precondition(hold(&s, at: nearEdge, for: 1.3, from: &t) == ["left"])
        hold(&s, at: nearEdge, for: 1.0, from: &t)                      // past the settling window
        hold(&s, at: CGPoint(x: 101, y: 380), for: frame, from: &t)   // one 40pt spike out
        precondition(hold(&s, at: nearEdge, for: 4, from: &t).isEmpty, "a jitter spike must not let a phrase repeat")
    }

    /// Settling latches what was under the resting cursor, not everything the
    /// person looks at in the next moment.
    static func aTargetLookedAtRightAfterASelectionStillWorks() {
        var s = DwellSelector()
        var t = 0.0
        precondition(hold(&s, at: leftCenter, for: 1.3, from: &t) == ["left"])
        precondition(hold(&s, at: rightCenter, for: 1.5, from: &t) == ["right"], "moving straight on to another phrase must work")
    }

    /// A blink pauses dwell; a long rest with the eyes shut does not leave a
    /// half-finished selection waiting to complete on reopening.
    static func aLongEyeClosureDropsProgress() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.9, from: &t)
        hold(&s, at: leftCenter, for: 3, from: &t, state: .eyesClosed)
        precondition(s.progress == 0, "a long closure must drop progress")
        precondition(hold(&s, at: leftCenter, for: 0.5, from: &t).isEmpty, "reopening must not complete the old dwell")
    }

    /// Seen in the simulator: onboarding finished, the board slid in, and its
    /// tiles registered after the 0.6 s settling window. The head was resting
    /// at the centre, the nearest tile snapped, and "Water" was spoken without
    /// being chosen. However long a new screen takes to register, what turns
    /// up under a cursor that has not moved was not chosen.
    static func aSlowScreenTransitionStillNeedsAFreshVisit() {
        var s = DwellSelector()
        var t = 0.0
        s.reset(time: t)
        hold(&s, at: leftCenter, for: 1.5, from: &t, targets: [])        // still sliding in
        precondition(hold(&s, at: leftCenter, for: 5, from: &t).isEmpty, "a slow transition must not turn a rest into a choice")
        hold(&s, at: CGPoint(x: 101, y: 500), for: 0.4, from: &t)
        precondition(hold(&s, at: leftCenter, for: 1.4, from: &t) == ["left"], "a deliberate visit still works")
    }

    /// The same, with the cursor resting in the gutter between two tiles,
    /// where snapping would otherwise pick one of them.
    static func restingInTheGutterAfterAScreenChangeSelectsNothing() {
        var s = DwellSelector()
        var t = 0.0
        let gutter = CGPoint(x: 196, y: 270)
        s.reset(time: t)
        hold(&s, at: gutter, for: 1.2, from: &t, targets: [])
        precondition(hold(&s, at: gutter, for: 5, from: &t).isEmpty, "resting in the gutter must not select a neighbour")
    }

    /// The resting rule ends as soon as the person moves: a target they then
    /// look at is a real choice even if it is near where they started.
    static func movingAwayEndsTheRestingRule() {
        var s = DwellSelector()
        var t = 0.0
        s.reset(time: t)
        hold(&s, at: CGPoint(x: 101, y: 500), for: 1.5, from: &t)       // rests on nothing
        precondition(hold(&s, at: leftCenter, for: 1.4, from: &t) == ["left"], "moving onto a tile is a choice")
    }

    /// Halfway across the gutter, either tile is as likely to be meant as the
    /// other. Snapping to the marginally nearer one is a coin flip that
    /// speaks the wrong phrase half the time.
    static func aCursorBetweenTwoTargetsSelectsNeither() {
        var s = DwellSelector()
        var t = 0.0
        precondition(hold(&s, at: CGPoint(x: 196, y: 270), for: 5, from: &t).isEmpty,
                     "a cursor equally between two tiles must not pick one")
        precondition(hold(&s, at: CGPoint(x: 197, y: 270), for: 5, from: &t).isEmpty,
                     "1pt off centre is still ambiguous")
    }

    /// HELP never snaps; a cursor in the gutter beside it must not snap to
    /// the button on its other side either. Seen in the simulator: Stop
    /// closed the HELP alert with the cursor resting between HELP and
    /// "I'm Okay", and "I'm okay" was spoken.
    static func aCursorBesideHelpDoesNotSnapToItsNeighbour() {
        var s = DwellSelector()
        var t = 0.0
        let okay = DwellTarget(id: "okay", frame: CGRect(x: 206, y: 700, width: 170, height: 60))
        let row = [help, okay]
        precondition(hold(&s, at: CGPoint(x: 196, y: 730), for: 5, from: &t, targets: row).isEmpty,
                     "the gutter between HELP and its neighbour selects nothing")
    }

    /// A cursor clearly closer to one tile is still a near miss of that tile.
    static func aClearNearMissInTheGutterStillSnaps() {
        var s = DwellSelector()
        var t = 0.0
        precondition(hold(&s, at: CGPoint(x: 189, y: 270), for: 1.5, from: &t) == ["left"],
                     "3pt outside one tile and 17pt from the other is that tile")
    }

    static func forgetsVanishedTargets() {
        var s = DwellSelector()
        var t = 0.0
        hold(&s, at: leftCenter, for: 0.8, from: &t)
        hold(&s, at: leftCenter, for: frame, from: &t, targets: [right, help])
        precondition(s.hoveredID == nil && s.progress == 0, "a hidden target cannot keep collecting dwell")
        s.reset(time: t)
        precondition(hold(&s, at: leftCenter, for: 0.5, from: &t).isEmpty, "reset starts a settling period")
    }
}

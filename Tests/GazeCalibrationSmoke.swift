import CoreGraphics
import Foundation

/// Calibration: per-axis direction and gain detection, validation, source
/// selection, re-centering, the directional check, and the accuracy summary.
@main
enum GazeCalibrationSmoke {
    static func main() {
        mapsThroughMeasuredPoints()
        acceptsAReversedButUsableAxis()
        rejectsUnusableAxes()
        builderDetectsDirectionGainAndBestSource()
        builderDetectsSwappedAxes()
        builderNeedsEnoughSamples()
        recenteringKeepsRangeAndDirection()
        directionalCheckJudgesTheCursor()
        filterDampsAOneFrameJump()
        accuracySummary()
        print("Gaze calibration smoke tests passed")
    }

    static func axis(_ low: CGFloat, _ center: CGFloat, _ high: CGFloat, jitter: CGFloat = 0.01) -> AxisCalibration {
        AxisCalibration(low: low, center: center, high: high, jitter: jitter, lowTarget: 0.14, highTarget: 0.86)
    }

    static func mapsThroughMeasuredPoints() {
        let x = axis(-0.7, 0.1, 1.1)
        precondition(abs(x.normalized(-0.7) - 0.14) < 1e-9)
        precondition(x.normalized(0.1) == 0.5)
        precondition(abs(x.normalized(1.1) - 0.86) < 1e-9)
        // Asymmetric halves each keep their own gain.
        precondition(abs(x.normalized(-0.3) - 0.32) < 1e-9)
        precondition(abs(x.normalized(0.6) - 0.68) < 1e-9)
        precondition(x.normalized(9) == 1 && x.normalized(-9) == 0, "must clamp")
    }

    /// The old validation assumed raw values rise from left to right and
    /// rejected anything else. A reversed signal with good range is usable.
    static func acceptsAReversedButUsableAxis() {
        let reversed = axis(0.3, 0.0, -0.3)
        precondition(reversed.isReversed)
        precondition(reversed.problem(minimumRange: 0.03) == nil, "a reversed axis with good range must be accepted")
        precondition(abs(reversed.normalized(0.3) - 0.14) < 1e-9, "the low target must still map to the left")
        precondition(abs(reversed.normalized(-0.3) - 0.86) < 1e-9, "the high target must still map to the right")
        precondition(reversed.normalized(0.15) < 0.5, "moving toward the low reading moves left")
    }

    static func rejectsUnusableAxes() {
        precondition(axis(0.10, 0.11, 0.12, jitter: 0).problem(minimumRange: 0.03) == .noResponse)
        precondition(axis(-0.3, 0.4, 0.3).problem(minimumRange: 0.03) == .crossedOver, "center outside the ends")
        precondition(axis(-0.3, 0.0, 0.3, jitter: 0.2).problem(minimumRange: 0.03) == .tooNoisy)
        // One good half and one dead half is not usable either.
        precondition(axis(-0.3, 0.0, 0.01, jitter: 0.001).problem(minimumRange: 0.03) == .noResponse)
    }

    /// Synthetic samples: the "person" looks at each target, the signal is a
    /// linear function of screen position plus deterministic noise.
    static func samples(
        gainX: CGFloat, gainY: CGFloat, offset: CGPoint = .zero, noise: CGFloat, swap: Bool = false, count: Int = 30
    ) -> [CalibrationPoint: [GazeSignalSet]] {
        var result: [CalibrationPoint: [GazeSignalSet]] = [:]
        for point in CalibrationPoint.allCases {
            let target = point.normalizedTarget
            result[point] = (0..<count).map { i in
                let wobble = noise * CGFloat(sin(Double(i) * 1.7) + cos(Double(i) * 2.3)) / 2
                var raw = CGPoint(x: offset.x + (target.x - 0.5) * gainX + wobble,
                                  y: offset.y + (target.y - 0.5) * gainY - wobble)
                if swap { raw = CGPoint(x: raw.y, y: raw.x) }
                // Blend shapes are steady; the eye ray is noisy; head pose absent.
                return GazeSignalSet(
                    headPose: nil,
                    eyeTransform: CGPoint(x: raw.x * 0.1, y: raw.y * 0.1 + wobble * 0.8),
                    lookAtPoint: nil,
                    blendShape: raw
                )
            }
        }
        return result
    }

    static func builderDetectsDirectionGainAndBestSource() {
        // Horizontal reversed (raw falls as the person looks right), vertical normal.
        let data = samples(gainX: -0.8, gainY: 0.6, offset: CGPoint(x: 0.05, y: -0.1), noise: 0.004)
        let outcome = GazeCalibrationBuilder.evaluate(samples: data, sources: [.eyeTransform, .lookAtPoint, .blendShape], orientation: .portrait)
        guard let best = outcome.best else { preconditionFailure("a usable source must be chosen") }
        precondition(best.source == .blendShape, "the steadiest source should win, got \(best.source)")
        precondition(best.x.isReversed && !best.y.isReversed, "direction must be detected per axis")
        precondition(!best.swapsAxes)
        let blend = outcome.evaluations.first { $0.source == .blendShape }!
        precondition(blend.xMatchesDocumentedDirection == false && blend.yMatchesDocumentedDirection == true)
        let lookAt = outcome.evaluations.first { $0.source == .lookAtPoint }!
        precondition(!lookAt.hasEnoughSamples && !lookAt.isUsable, "a missing source is reported, not chosen")

        // Looking at each target now lands the cursor on it.
        for point in CalibrationPoint.allCases {
            let raw = CGPoint(x: 0.05 + (point.normalizedTarget.x - 0.5) * -0.8,
                              y: -0.1 + (point.normalizedTarget.y - 0.5) * 0.6)
            let mapped = best.normalizedPoint(for: raw)
            precondition(hypot(mapped.x - point.normalizedTarget.x, mapped.y - point.normalizedTarget.y) < 0.02,
                         "\(point) mapped to \(mapped)")
        }
        precondition(best.isValid)
        let decoded = try! JSONDecoder().decode(GazeCalibration.self, from: JSONEncoder().encode(best))
        precondition(decoded == best, "calibration must survive a save and load")
    }

    static func builderDetectsSwappedAxes() {
        let data = samples(gainX: 0.8, gainY: 0.6, noise: 0.002, swap: true)
        let outcome = GazeCalibrationBuilder.evaluate(samples: data, sources: [.blendShape], orientation: .landscapeLeft)
        guard let best = outcome.best else { preconditionFailure("swapped axes should still calibrate") }
        precondition(best.swapsAxes)
        let raw = CGPoint(x: (0.84 - 0.5) * 0.6, y: (0.14 - 0.5) * 0.8)   // swapped: looking bottom-left
        let mapped = best.normalizedPoint(for: raw)
        precondition(abs(mapped.x - 0.14) < 0.02 && abs(mapped.y - 0.84) < 0.02, "swapped mapping put \(raw) at \(mapped)")
    }

    static func builderNeedsEnoughSamples() {
        let data = samples(gainX: 0.8, gainY: 0.6, noise: 0.002, count: 6)
        let outcome = GazeCalibrationBuilder.evaluate(samples: data, sources: [.blendShape], orientation: .portrait)
        precondition(outcome.best == nil && !outcome.evaluations[0].hasEnoughSamples)
    }

    static func recenteringKeepsRangeAndDirection() {
        let calibration = GazeCalibration(source: .headPose, x: axis(0.3, 0, -0.3), y: axis(-0.2, 0, 0.2),
                                          orientation: .portrait, createdAt: Date(timeIntervalSince1970: 0))
        let moved = calibration.recentered(on: CGPoint(x: 0.1, y: -0.05))
        precondition(moved.normalizedPoint(for: CGPoint(x: 0.1, y: -0.05)) == CGPoint(x: 0.5, y: 0.5))
        precondition(moved.x.isReversed && abs(abs(moved.x.high - moved.x.low) - 0.6) < 1e-9)
        precondition(moved.isValid)
    }

    static func directionalCheckJudgesTheCursor() {
        let good = DirectionalCheckResult(center: CGPoint(x: 0.5, y: 0.5), left: CGPoint(x: 0.2, y: 0.5),
                                          right: CGPoint(x: 0.8, y: 0.52), up: CGPoint(x: 0.5, y: 0.22), down: CGPoint(x: 0.49, y: 0.8))
        precondition(good.allPassed)
        // The reported bug: looking left moves the cursor right, up moves it down.
        let reversed = DirectionalCheckResult(center: CGPoint(x: 0.5, y: 0.5), left: CGPoint(x: 0.8, y: 0.5),
                                              right: CGPoint(x: 0.2, y: 0.5), up: CGPoint(x: 0.5, y: 0.8), down: CGPoint(x: 0.5, y: 0.2))
        precondition(!reversed.left && !reversed.right && !reversed.up && !reversed.down)
        // Barely moving is not passing.
        let timid = DirectionalCheckResult(center: CGPoint(x: 0.5, y: 0.5), left: CGPoint(x: 0.45, y: 0.5),
                                           right: CGPoint(x: 0.55, y: 0.5), up: CGPoint(x: 0.5, y: 0.45), down: CGPoint(x: 0.5, y: 0.55))
        precondition(!timid.left && !timid.right && !timid.up && !timid.down)
    }

    static func filterDampsAOneFrameJump() {
        var filter = AdaptiveGazeFilter()
        precondition(filter.filter(0, at: 0) == 0)
        let noisy = filter.filter(10, at: 1.0 / 60.0)
        precondition(noisy > 0 && noisy < 10, "filter should damp a one-frame jump")
        filter.reset()
        precondition(filter.filter(5, at: 2) == 5, "reset forgets history")
    }

    static func accuracySummary() {
        let accuracy = GazeAccuracyResult(
            trackingMode: "eye",
            trials: [
                GazeAccuracyTrial(target: CGPoint(x: 0.25, y: 0.25),
                                  samples: Array(repeating: CGPoint(x: 0.26, y: 0.25), count: 15),
                                  duration: 1.2, succeeded: true),
                GazeAccuracyTrial(target: CGPoint(x: 0.75, y: 0.75),
                                  samples: Array(repeating: CGPoint(x: 0.9, y: 0.9), count: 15),
                                  duration: 6, succeeded: false, wrongSelections: 1, trackingLosses: 2)
            ],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        precondition(accuracy.targetCount == 2 && accuracy.successfulTargets == 1)
        precondition(accuracy.successRate == 0.5)
        precondition(accuracy.meanErrorPercent > 0 && accuracy.meanJitterPercent < 1e-6)
        precondition(abs(accuracy.meanAcquisitionTime - 1.2) < 1e-9, "timeouts must not count as acquisition time")
        precondition(accuracy.falseSelections == 1 && accuracy.trackingLosses == 2)
        precondition(try! JSONDecoder().decode(GazeAccuracyResult.self, from: JSONEncoder().encode(accuracy)) == accuracy)
    }
}

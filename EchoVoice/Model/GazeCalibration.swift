import CoreGraphics
import Foundation

/// The five on-screen points calibration measures.
enum CalibrationPoint: String, CaseIterable, Codable, Sendable {
    case center, left, right, top, bottom

    /// Where the target is drawn, as a fraction of the gaze area.
    var normalizedTarget: CGPoint {
        switch self {
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .left: return CGPoint(x: 0.14, y: 0.5)
        case .right: return CGPoint(x: 0.86, y: 0.5)
        case .top: return CGPoint(x: 0.5, y: 0.16)
        case .bottom: return CGPoint(x: 0.5, y: 0.84)
        }
    }
}

/// One axis of a calibration: the raw signal measured at the low target (left
/// or top), the center, and the high target (right or bottom).
///
/// Direction is *measured*, never assumed. If a device, a mount, or a person's
/// anatomy makes the raw value fall as they look right, `high` is simply below
/// `low` and the mapping still lands the cursor on the right. What makes an
/// axis unusable is a signal that does not respond, that crosses over (center
/// not between the ends), or that is too noisy relative to its range.
struct AxisCalibration: Codable, Equatable, Sendable {
    var low: CGFloat
    var center: CGFloat
    var high: CGFloat
    /// Typical sample-to-sample spread while holding still (robust estimate).
    var jitter: CGFloat
    /// Normalized screen positions of the low and high targets.
    var lowTarget: CGFloat
    var highTarget: CGFloat

    enum Problem: String, Codable, Equatable, Sendable {
        case noResponse
        case crossedOver
        case tooNoisy
    }

    /// Each half-range must be at least this many times the jitter.
    static let minimumSignalToNoise: CGFloat = 3

    var isReversed: Bool { high < low }

    var isMonotonic: Bool {
        (low < center && center < high) || (low > center && center > high)
    }

    var smallestHalfRange: CGFloat {
        min(abs(center - low), abs(high - center))
    }

    var signalToNoise: CGFloat {
        guard jitter > 0 else { return smallestHalfRange > 0 ? .greatestFiniteMagnitude : 0 }
        return smallestHalfRange / jitter
    }

    func problem(minimumRange: CGFloat) -> Problem? {
        if abs(high - low) < minimumRange * 2 { return .noResponse }
        if !isMonotonic { return .crossedOver }
        if smallestHalfRange < minimumRange { return .noResponse }
        if signalToNoise < Self.minimumSignalToNoise { return .tooNoisy }
        return nil
    }

    /// Piecewise-linear mapping through the three measured points, so the
    /// center stays accurate even when left and right ranges differ.
    func normalized(_ value: CGFloat) -> CGFloat {
        let offset = value - center
        guard offset != 0 else { return 0.5 }
        let mapped: CGFloat
        if offset * (high - center) > 0 {
            mapped = 0.5 + (highTarget - 0.5) * offset / (high - center)
        } else {
            mapped = 0.5 + (lowTarget - 0.5) * offset / (low - center)
        }
        return min(max(mapped, 0), 1)
    }

    func shifted(by delta: CGFloat) -> AxisCalibration {
        AxisCalibration(low: low + delta, center: center + delta, high: high + delta,
                        jitter: jitter, lowTarget: lowTarget, highTarget: highTarget)
    }
}

/// A person's calibrated mapping from one signal source to the screen.
struct GazeCalibration: Codable, Equatable, Sendable {
    /// Bumped whenever the meaning of a raw signal changes. A calibration
    /// measured against a different signal definition is meaningless.
    static let currentFormatVersion = 2

    var formatVersion: Int = GazeCalibration.currentFormatVersion
    var source: GazeSignalSource
    var x: AxisCalibration
    var y: AxisCalibration
    /// True when the screen's horizontal axis was measured on the raw signal's
    /// vertical component (and vice versa) — what a camera mounted at 90° to
    /// the expected orientation produces. Detected, not assumed.
    var swapsAxes: Bool = false
    var orientation: GazeScreenOrientation
    var createdAt: Date

    /// Below this the signal is treated as not responding at all.
    static func minimumRange(for source: GazeSignalSource) -> CGFloat {
        switch source {
        case .headPose: return 0.03          // ≈ 1.7°
        case .eyeTransform, .lookAtPoint: return 0.003   // 3 mm on the device plane
        case .blendShape: return 0.02
        }
    }

    var xProblem: AxisCalibration.Problem? { x.problem(minimumRange: Self.minimumRange(for: source)) }
    var yProblem: AxisCalibration.Problem? { y.problem(minimumRange: Self.minimumRange(for: source)) }

    var isValid: Bool {
        formatVersion == Self.currentFormatVersion && xProblem == nil && yProblem == nil
    }

    /// The raw value that maps to the screen center, in raw-signal axes.
    var neutral: CGPoint {
        swapsAxes ? CGPoint(x: y.center, y: x.center) : CGPoint(x: x.center, y: y.center)
    }

    func normalizedPoint(for raw: CGPoint) -> CGPoint {
        let (horizontal, vertical) = swapsAxes ? (raw.y, raw.x) : (raw.x, raw.y)
        return CGPoint(x: x.normalized(horizontal), y: y.normalized(vertical))
    }

    /// Keep the measured range and direction, but treat `raw` as the new
    /// center. Used to re-center after someone shifts in a chair or bed
    /// without redoing the whole calibration.
    func recentered(on raw: CGPoint) -> GazeCalibration {
        let (horizontal, vertical) = swapsAxes ? (raw.y, raw.x) : (raw.x, raw.y)
        var copy = self
        copy.x = x.shifted(by: horizontal - x.center)
        copy.y = y.shifted(by: vertical - y.center)
        return copy
    }
}

/// How one source performed in a calibration, reported for setup and for
/// the Signal Check tool.
struct GazeCalibrationEvaluation: Equatable, Sendable {
    let source: GazeSignalSource
    /// Built whenever enough samples exist, valid or not.
    let candidate: GazeCalibration?
    let xProblem: AxisCalibration.Problem?
    let yProblem: AxisCalibration.Problem?
    let hasEnoughSamples: Bool

    var isUsable: Bool { hasEnoughSamples && xProblem == nil && yProblem == nil && candidate != nil }

    /// The weaker axis's signal-to-noise ratio. Higher is steadier.
    var score: CGFloat {
        guard let candidate else { return 0 }
        return min(candidate.x.signalToNoise, candidate.y.signalToNoise)
    }

    /// Whether the measured direction matches Apple's documented conventions
    /// as interpreted in `GazeSignals.swift`. A `false` here does not break
    /// anything — calibration corrects it — but it is exactly the evidence
    /// needed when a device behaves unexpectedly.
    var xMatchesDocumentedDirection: Bool? { candidate.map { !$0.x.isReversed } }
    var yMatchesDocumentedDirection: Bool? { candidate.map { !$0.y.isReversed } }
}

enum GazeCalibrationBuilder {
    /// The first part of each target's samples is discarded: eyes take a
    /// moment to land on a new target, and heads longer.
    static let settleFraction = 0.25
    static let minimumSamplesPerPoint = 8

    static func evaluate(
        samples: [CalibrationPoint: [GazeSignalSet]],
        sources: [GazeSignalSource],
        orientation: GazeScreenOrientation,
        createdAt: Date = .now
    ) -> (best: GazeCalibration?, evaluations: [GazeCalibrationEvaluation]) {
        let evaluations = sources.map { evaluate(source: $0, samples: samples, orientation: orientation, createdAt: createdAt) }
        return (chooseBest(evaluations, preferenceOrder: sources), evaluations)
    }

    /// The steadiest usable source wins. A source earlier in the preference
    /// order keeps the win when it is within 15% of the best score, so a
    /// marginal difference does not flip the method between calibrations.
    static func chooseBest(_ evaluations: [GazeCalibrationEvaluation], preferenceOrder: [GazeSignalSource]) -> GazeCalibration? {
        let usable = evaluations.filter(\.isUsable)
        guard let topScore = usable.map(\.score).max() else { return nil }
        for source in preferenceOrder {
            if let match = usable.first(where: { $0.source == source }), match.score >= topScore * 0.85 {
                return match.candidate
            }
        }
        return usable.max(by: { $0.score < $1.score })?.candidate
    }

    static func evaluate(
        source: GazeSignalSource,
        samples: [CalibrationPoint: [GazeSignalSet]],
        orientation: GazeScreenOrientation,
        createdAt: Date
    ) -> GazeCalibrationEvaluation {
        var stats: [CalibrationPoint: PointStats] = [:]
        for point in CalibrationPoint.allCases {
            let values = (samples[point] ?? []).compactMap { $0[source] }
            let settled = Array(values.dropFirst(Int(Double(values.count) * settleFraction)))
            guard settled.count >= minimumSamplesPerPoint else {
                return GazeCalibrationEvaluation(source: source, candidate: nil, xProblem: nil, yProblem: nil, hasEnoughSamples: false)
            }
            stats[point] = PointStats(settled)
        }
        guard let c = stats[.center], let l = stats[.left], let r = stats[.right],
              let t = stats[.top], let b = stats[.bottom] else {
            return GazeCalibrationEvaluation(source: source, candidate: nil, xProblem: nil, yProblem: nil, hasEnoughSamples: false)
        }

        let direct = candidate(source: source, c: c, l: l, r: r, t: t, b: b, swapped: false, orientation: orientation, createdAt: createdAt)
        let swapped = candidate(source: source, c: c, l: l, r: r, t: t, b: b, swapped: true, orientation: orientation, createdAt: createdAt)
        // The direct assignment is the documented one, so it wins whenever it
        // works. Swapped axes are only used when they work and direct does not.
        let chosen = (!direct.isValid && swapped.isValid) ? swapped : direct
        return GazeCalibrationEvaluation(
            source: source,
            candidate: chosen,
            xProblem: chosen.xProblem,
            yProblem: chosen.yProblem,
            hasEnoughSamples: true
        )
    }

    private static func candidate(
        source: GazeSignalSource,
        c: PointStats, l: PointStats, r: PointStats, t: PointStats, b: PointStats,
        swapped: Bool,
        orientation: GazeScreenOrientation,
        createdAt: Date
    ) -> GazeCalibration {
        // Horizontal targets read the component that should move horizontally.
        func h(_ p: CGPoint) -> CGFloat { swapped ? p.y : p.x }
        func v(_ p: CGPoint) -> CGFloat { swapped ? p.x : p.y }
        let x = AxisCalibration(
            low: h(l.median), center: h(c.median), high: h(r.median),
            jitter: (h(c.spread) + h(l.spread) + h(r.spread)) / 3,
            lowTarget: CalibrationPoint.left.normalizedTarget.x,
            highTarget: CalibrationPoint.right.normalizedTarget.x
        )
        let y = AxisCalibration(
            low: v(t.median), center: v(c.median), high: v(b.median),
            jitter: (v(c.spread) + v(t.spread) + v(b.spread)) / 3,
            lowTarget: CalibrationPoint.top.normalizedTarget.y,
            highTarget: CalibrationPoint.bottom.normalizedTarget.y
        )
        return GazeCalibration(source: source, x: x, y: y, swapsAxes: swapped, orientation: orientation, createdAt: createdAt)
    }
}

/// Median and robust spread of a set of 2D samples.
struct PointStats: Equatable, Sendable {
    let median: CGPoint
    /// Median absolute deviation, scaled to match a standard deviation for
    /// normally distributed noise. A single wild frame barely moves it.
    let spread: CGPoint

    init(_ points: [CGPoint]) {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let mx = Self.median(xs)
        let my = Self.median(ys)
        median = CGPoint(x: mx, y: my)
        spread = CGPoint(
            x: Self.median(xs.map { abs($0 - mx) }) * 1.4826,
            y: Self.median(ys.map { abs($0 - my) }) * 1.4826
        )
    }

    static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// Whether the calibrated cursor actually goes where the person looks.
///
/// Calibration fits a mapping; this checks the result the way a person would,
/// by looking at each edge and seeing which side of center the cursor lands.
struct DirectionalCheckResult: Codable, Equatable, Sendable {
    var left: Bool
    var right: Bool
    var up: Bool
    var down: Bool

    var allPassed: Bool { left && right && up && down }

    /// The cursor must move at least this far from where it sat at center,
    /// and end on the correct side of the screen.
    static let minimumTravel: CGFloat = 0.12

    /// Inputs are the cursor's median normalized position during each step.
    init(center: CGPoint, left: CGPoint, right: CGPoint, up: CGPoint, down: CGPoint) {
        let travel = Self.minimumTravel
        self.left = left.x < center.x - travel && left.x < 0.42
        self.right = right.x > center.x + travel && right.x > 0.58
        self.up = up.y < center.y - travel && up.y < 0.42
        self.down = down.y > center.y + travel && down.y > 0.58
    }

    init(left: Bool, right: Bool, up: Bool, down: Bool) {
        self.left = left
        self.right = right
        self.up = up
        self.down = down
    }
}

/// One Euro filter: steady gaze is smoothed heavily while deliberate fast
/// movement stays responsive. No dependency or remote processing required.
struct AdaptiveGazeFilter: Sendable {
    /// Cutoff frequency at rest, in Hz. Lower is steadier and laggier.
    var minimumCutoff: CGFloat = 1.15
    /// How quickly the cutoff rises with speed (per point per second).
    var speedCoefficient: CGFloat = 0.025

    private var previousRaw: CGFloat?
    private var previousFiltered: CGFloat?
    private var previousDerivative: CGFloat = 0
    private var previousTime: TimeInterval?

    init(minimumCutoff: CGFloat = 1.15, speedCoefficient: CGFloat = 0.025) {
        self.minimumCutoff = minimumCutoff
        self.speedCoefficient = speedCoefficient
    }

    mutating func filter(_ value: CGFloat, at time: TimeInterval) -> CGFloat {
        guard let previousRaw, let previousFiltered, let previousTime else {
            self.previousRaw = value
            self.previousFiltered = value
            self.previousTime = time
            return value
        }

        let interval = max(time - previousTime, 1.0 / 120.0)
        let derivative = (value - previousRaw) / interval
        let filteredDerivative = lowPass(previousDerivative, derivative, alpha: alpha(cutoff: 1, interval: interval))
        let cutoff = minimumCutoff + speedCoefficient * abs(filteredDerivative)
        let filtered = lowPass(previousFiltered, value, alpha: alpha(cutoff: cutoff, interval: interval))

        self.previousRaw = value
        self.previousFiltered = filtered
        self.previousDerivative = filteredDerivative
        self.previousTime = time
        return filtered
    }

    mutating func reset() {
        previousRaw = nil
        previousFiltered = nil
        previousDerivative = 0
        previousTime = nil
    }

    private func alpha(cutoff: CGFloat, interval: TimeInterval) -> CGFloat {
        let tau = 1 / (2 * .pi * cutoff)
        return CGFloat(interval) / (CGFloat(interval) + tau)
    }

    private func lowPass(_ previous: CGFloat, _ value: CGFloat, alpha: CGFloat) -> CGFloat {
        previous + alpha * (value - previous)
    }
}

/// One target in the accuracy check.
struct GazeAccuracyTrial: Sendable {
    let target: CGPoint
    /// Normalized cursor positions while the target was shown.
    let samples: [CGPoint]
    let duration: TimeInterval
    let succeeded: Bool
    /// Dwell selections that completed on a neighbouring target instead.
    var wrongSelections: Int = 0
    /// Times tracking dropped out for longer than the dwell grace period.
    var trackingLosses: Int = 0
}

/// Aggregate evidence from an accuracy check. Raw gaze samples are discarded.
struct GazeAccuracyResult: Codable, Equatable, Sendable {
    let trackingMode: String
    let targetCount: Int
    let successfulTargets: Int
    let meanErrorPercent: Double
    let meanJitterPercent: Double
    let meanAcquisitionTime: TimeInterval
    /// Selections that landed on the wrong target, across all trials.
    let falseSelections: Int
    let trackingLosses: Int
    let createdAt: Date

    var successRate: Double {
        targetCount == 0 ? 0 : Double(successfulTargets) / Double(targetCount)
    }

    init(trackingMode: String, trials: [GazeAccuracyTrial], createdAt: Date = .now) {
        let measured = trials.filter { !$0.samples.isEmpty }
        let errors = measured.map { trial in
            let finalSamples = Array(trial.samples.suffix(15))
            return finalSamples.reduce(0) {
                $0 + hypot($1.x - trial.target.x, $1.y - trial.target.y)
            } / Double(finalSamples.count) / sqrt(2) * 100
        }
        let jitters = measured.map { trial in
            let finalSamples = Array(trial.samples.suffix(15))
            let total = finalSamples.reduce(CGPoint.zero) {
                CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
            }
            let average = CGPoint(
                x: total.x / CGFloat(finalSamples.count),
                y: total.y / CGFloat(finalSamples.count)
            )
            return finalSamples.reduce(0) {
                $0 + hypot($1.x - average.x, $1.y - average.y)
            } / Double(finalSamples.count) / sqrt(2) * 100
        }

        self.trackingMode = trackingMode
        self.targetCount = trials.count
        self.successfulTargets = trials.filter(\.succeeded).count
        self.meanErrorPercent = errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count)
        self.meanJitterPercent = jitters.isEmpty ? 0 : jitters.reduce(0, +) / Double(jitters.count)
        // Only successful trials say how long selection takes; a timed-out
        // trial would report the timeout, not the person.
        let successes = trials.filter(\.succeeded)
        self.meanAcquisitionTime = successes.isEmpty ? 0 : successes.map(\.duration).reduce(0, +) / Double(successes.count)
        self.falseSelections = trials.map(\.wrongSelections).reduce(0, +)
        self.trackingLosses = trials.map(\.trackingLosses).reduce(0, +)
        self.createdAt = createdAt
    }
}

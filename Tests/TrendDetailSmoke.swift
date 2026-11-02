import Foundation

/// Tests the numbers behind the journal's detail panel.
///
/// The panel exists so a reading can be brought to a clinician as evidence
/// rather than as a verdict. That only holds if what it displays is the same
/// arithmetic that produced the flag — a panel that quietly recomputes things
/// its own way would be worse than no panel, because it would look authoritative
/// while disagreeing with the app.
@main
struct TrendDetailSmoke {
    static func main() {
        checkSilentWithoutBaseline()
        checkAgreesWithAnalyze()
        checkNoiseFloorIsDisclosed()
        checkPauseUsesItsOwnRule()
        checkSampleHistoryIsDeterministic()
        checkSampleHistoryBuildsThenDeclines()
        print("Trend detail smoke tests passed")
    }

    private static func steady(_ wpm: Double) -> CheckinMetrics {
        CheckinMetrics(wpm: wpm, pauseRatio: 0.15, pitchStability: 0.6)
    }

    /// Fewer than three prior readings is not a baseline, and the panel must say
    /// so rather than render zeroes that look like measurements.
    private static func checkSilentWithoutBaseline() {
        let detail = SpeechTrend.detail(history: [steady(150), steady(148)], latest: steady(100))
        precondition(!detail.hasBaseline, "claimed a baseline from two readings")
        precondition(detail.comparisons.isEmpty, "produced comparisons with no baseline to compare against")
    }

    /// The panel's per-metric flags must match the verdict `analyze` reached.
    private static func checkAgreesWithAnalyze() {
        let history = [steady(150), steady(146), steady(152), steady(149)]
        let dropped = CheckinMetrics(wpm: 96, pauseRatio: 0.15, pitchStability: 0.6)

        let verdict = SpeechTrend.analyze(history: history, latest: dropped)
        let detail = SpeechTrend.detail(history: history, latest: dropped)

        precondition(verdict.flagged, "a large rate drop was not flagged at all")
        guard let rate = detail.comparisons.first(where: { $0.name == "Speaking rate" }) else {
            preconditionFailure("no speaking-rate comparison was produced")
        }
        precondition(rate.crossedThreshold, "the panel disagreed with the flag the app acted on")
        precondition(rate.z > SpeechTrend.zThreshold, "z-score is below the threshold it supposedly crossed")
        precondition(abs(rate.latest - 96) < 0.001, "the panel showed a different reading than was analyzed")

        // And the converse: a normal reading must not be marked.
        let normalDetail = SpeechTrend.detail(history: history, latest: steady(147))
        precondition(
            normalDetail.comparisons.allSatisfy { !$0.crossedThreshold },
            "an ordinary reading was marked as having crossed a threshold"
        )
    }

    /// Near-identical history drives the standard deviation toward zero, and the
    /// noise floor takes over. The panel has to disclose that, or a soft signal
    /// reads as a hard one.
    private static func checkNoiseFloorIsDisclosed() {
        let identical = [steady(150), steady(150), steady(150), steady(150)]
        let detail = SpeechTrend.detail(history: identical, latest: steady(120))
        guard let rate = detail.comparisons.first(where: { $0.name == "Speaking rate" }) else {
            preconditionFailure("no speaking-rate comparison was produced")
        }
        precondition(rate.usedNoiseFloor, "the noise floor was applied without being disclosed")
        precondition(rate.baselineStd < rate.noiseFloor, "usedNoiseFloor was set without the floor applying")
        precondition(rate.z.isFinite, "a zero-variance baseline produced a non-finite z-score")
    }

    /// Pausing deliberately does not use the z threshold — near-zero pause
    /// ratios make standard deviations misleading — so the panel must apply the
    /// same relative rule `analyze` uses.
    private static func checkPauseUsesItsOwnRule() {
        let history = [
            CheckinMetrics(wpm: 150, pauseRatio: 0.10, pitchStability: 0.6),
            CheckinMetrics(wpm: 150, pauseRatio: 0.11, pitchStability: 0.6),
            CheckinMetrics(wpm: 150, pauseRatio: 0.09, pitchStability: 0.6),
            CheckinMetrics(wpm: 150, pauseRatio: 0.10, pitchStability: 0.6)
        ]
        // Above 1.4x the baseline but below the absolute 0.25 floor: a large
        // relative jump in a person who barely pauses is not worth alarming over.
        let smallRise = CheckinMetrics(wpm: 150, pauseRatio: 0.20, pitchStability: 0.6)
        let smallDetail = SpeechTrend.detail(history: history, latest: smallRise)
        precondition(
            smallDetail.comparisons.first(where: { $0.name == "Pausing" })?.crossedThreshold == false,
            "flagged a pause rise that stayed under the absolute floor"
        )

        let realRise = CheckinMetrics(wpm: 150, pauseRatio: 0.42, pitchStability: 0.6)
        let realDetail = SpeechTrend.detail(history: history, latest: realRise)
        precondition(
            realDetail.comparisons.first(where: { $0.name == "Pausing" })?.crossedThreshold == true,
            "missed a pause rise that cleared both parts of the rule"
        )
        precondition(
            SpeechTrend.analyze(history: history, latest: realRise).flagged,
            "the panel and the analyzer disagree about the same pause rise"
        )
    }

    /// A demonstration has to be reproducible: the same seed must give the same
    /// curve, or a screenshot can never be retaken.
    private static func checkSampleHistoryIsDeterministic() {
        let anchor = Date(timeIntervalSince1970: 1_790_000_000)
        let first = SampleJournalHistory.readings(endingAt: anchor).map(\.metrics.wpm)
        let second = SampleJournalHistory.readings(endingAt: anchor).map(\.metrics.wpm)
        precondition(first == second, "sample history changed between runs")
        precondition(first.count == SampleJournalHistory.readingCount, "wrong number of sample readings")
    }

    /// The sample curve is only worth shipping if the shipping analyzer actually
    /// flags it — otherwise the demonstration shows a feature not working.
    private static func checkSampleHistoryBuildsThenDeclines() {
        let readings = SampleJournalHistory.readings(endingAt: Date(timeIntervalSince1970: 1_790_000_000))
        var accumulated: [CheckinMetrics] = []
        var flaggedEarly = 0
        var flaggedLate = false

        for (index, reading) in readings.enumerated() {
            let latest = CheckinMetrics(
                wpm: reading.metrics.wpm,
                pauseRatio: reading.metrics.pauseRatio,
                pitchStability: reading.metrics.pitchStability
            )
            let verdict = SpeechTrend.analyze(history: accumulated, latest: latest)
            if index < 9, verdict.flagged { flaggedEarly += 1 }
            if index == readings.count - 1, verdict.flagged { flaggedLate = true }
            accumulated.append(latest)
        }

        precondition(flaggedEarly == 0, "the steady stretch of the sample history was flagged")
        precondition(flaggedLate, "the sample history's decline was never flagged")

        // Chronological order matters: the chart and the baseline both assume it.
        let dates = readings.map(\.date)
        precondition(dates == dates.sorted(), "sample readings were not in date order")
    }
}

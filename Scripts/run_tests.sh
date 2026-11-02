#!/bin/bash
#
# Runs every EchoVoice logic test.
#
# The tests are standalone Swift executables rather than an XCTest bundle, so
# they need no simulator, no signing, and no Xcode UI — which means they can be
# run on any Mac in a few seconds, including by someone verifying the project
# who has never opened it before.
#
# Each test compiles only the source files it exercises. That is deliberate: it
# proves the logic under test has no hidden dependency on SwiftUI, SwiftData, or
# the app's object graph. Anything that needs the whole app is a view, and views
# are verified by building the app (Scripts/build.sh equivalent below).
#
# Usage: ./Scripts/run_tests.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="$ROOT/EchoVoice/Model"
TESTS="$ROOT/Tests"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# Extra swiftc flags for the next run_suite call. Reset after each use.
SUITE_FLAGS=()

run_suite() {
  local name="$1"; shift
  local out="$WORK/$name"
  local src="$WORK/src-$name"

  # Compile from copies rather than the working tree. swiftc compares source
  # mtimes against its own build clock and aborts with "input file was modified
  # during the build" when a file was saved in the same second the compile
  # starts — which happens constantly while editing. Copying also guarantees a
  # suite cannot accidentally pick up a file it did not declare.
  mkdir -p "$src"
  local sources=()
  for file in "$@"; do
    cp "$file" "$src/"
    sources+=("$src/$(basename "$file")")
  done

  if ! swiftc -O ${SUITE_FLAGS[@]+"${SUITE_FLAGS[@]}"} "${sources[@]}" -o "$out" 2> "$WORK/$name.compile.log"; then
    echo "  FAIL  $name (did not compile)"
    sed 's/^/        /' "$WORK/$name.compile.log" | head -20
    fail=$((fail + 1))
    return
  fi

  if "$out" > "$WORK/$name.run.log" 2>&1; then
    echo "  ok    $name"
    pass=$((pass + 1))
  else
    echo "  FAIL  $name"
    sed 's/^/        /' "$WORK/$name.run.log" | head -20
    fail=$((fail + 1))
  fi
  SUITE_FLAGS=()
}

echo "EchoVoice logic tests"
echo

# Signal processing on a recorded reading.
run_suite speech-analysis \
  "$TESTS/SpeechAnalysisSmoke.swift" \
  "$MODEL/SpeechAnalysis.swift"

# The streaming path behind the live waveform agrees with the saved analysis.
run_suite live-trace \
  "$TESTS/LiveTraceSmoke.swift" \
  "$MODEL/LiveSpeechTrace.swift" \
  "$MODEL/SpeechAnalysis.swift"

# Personal-baseline comparison, and the numbers the detail panel displays.
run_suite trend-detail \
  "$TESTS/TrendDetailSmoke.swift" \
  "$MODEL/SpeechTrend.swift" \
  "$MODEL/SpeechAnalysis.swift" \
  "$MODEL/SampleJournalHistory.swift"

# The suggestion ranker, and that its explanation matches its ranking.
run_suite suggestion-explainability \
  "$TESTS/SuggestionExplainabilitySmoke.swift" \
  "$MODEL/AdaptivePhraseRanker.swift"

# Ranking behavior: learns from use, time of day, and never invents phrases.
run_suite adaptive-ranker \
  "$TESTS/AdaptivePhraseRankerSmoke.swift" \
  "$MODEL/AdaptivePhraseRanker.swift"

# The guardrail preventing the sentence expander adding meaning.
run_suite sentence-guardrail \
  "$TESTS/SentenceGuardrailSmoke.swift" \
  "$MODEL/SentenceExpander.swift" \
  "$MODEL/AppLanguage.swift"

# Adult AAC vocabulary: category shape and personal-message substitution.
run_suite aac-vocabulary \
  "$TESTS/AACVocabularySmoke.swift" \
  "$MODEL/AACVocabulary.swift"

# Hands-free coordinate mapping: ARKit face/camera axes to screen directions,
# for every interface orientation and every signal source.
run_suite board-layout \
  "$TESTS/BoardLayoutSmoke.swift" \
  "$MODEL/BoardLayout.swift"

run_suite gaze-signals \
  "$TESTS/GazeSignalsSmoke.swift" \
  "$MODEL/GazeSignals.swift"

# Calibration: per-axis direction and gain detection, source choice, checks.
run_suite gaze-calibration \
  "$TESTS/GazeCalibrationSmoke.swift" \
  "$MODEL/GazeCalibration.swift" \
  "$MODEL/GazeSignals.swift"

# Dwell selection safety: snapping, hysteresis, blinks, loss, HELP.
run_suite dwell-selector \
  "$TESTS/DwellSelectorSmoke.swift" \
  "$MODEL/DwellSelector.swift"

# Blink gestures: ordinary blinking must never call HELP.
run_suite blink-gesture \
  "$TESTS/BlinkGestureSmoke.swift" \
  "$MODEL/BlinkGestureDetector.swift"

# Trend flagging and voice-banking urgency, against stub models.
run_suite core-logic \
  "$TESTS/CoreLogicSmoke.swift" \
  "$MODEL/SpeechTrend.swift" \
  "$MODEL/BankingUrgency.swift"

# Banked-recording quality check: clipping, level, noise, cut-off speech.
run_suite recording-quality \
  "$TESTS/RecordingQualitySmoke.swift" \
  "$MODEL/RecordingQuality.swift" \
  "$MODEL/SpeechAnalysis.swift"

# Listen mode: partner's words to yes/no, choices, and board-phrase replies.
run_suite partner-reply \
  "$TESTS/PartnerReplySmoke.swift" \
  "$MODEL/PartnerReplySuggester.swift"

# Room-aware volume: never below the person's setting, stale readings ignored.
run_suite adaptive-volume \
  "$TESTS/AdaptiveVolumeSmoke.swift" \
  "$MODEL/AdaptiveVolume.swift" \
  "$MODEL/RecordingQuality.swift" \
  "$MODEL/SpeechAnalysis.swift"

# Voice keepsake file naming and copying; Listen's conversation timeline.
run_suite voice-keepsake \
  "$TESTS/VoiceKeepsakeSmoke.swift" \
  "$MODEL/VoiceKeepsake.swift" \
  "$MODEL/ConversationTimeline.swift"

# Export/import round trip for a message bank. Needs ECHOVOICE_TESTING so
# AudioFileManager will write into a scratch directory instead of the real
# recordings folder — the override is compiled out of shipping builds.
SUITE_FLAGS=(-D ECHOVOICE_TESTING)
run_suite message-bank \
  "$TESTS/MessageBankSmoke.swift" \
  "$MODEL/AudioFileManager.swift"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

# iPad layout notes

Audited every Swift file in `EchoVoice/Views`. Regular horizontal size classes
use the layouts below; compact widths retain the phone layouts for Split View
and Slide Over. No device-model or full-screen-size assumptions were added.

| Screen / file | Change |
| --- | --- |
| `SpeakBoardView` — Quick, Build, categories, Personal | Adaptive columns with Dynamic Type-scaled minimum widths; page counts follow available width and height. Hands-free Build targets have larger minimum heights and gutters. Category overflow scrolls. Tile measurements and dwell reset when layout changes. |
| `SpeakBoardView` — HELP, workspace, mode controls | Width limits for controls and workspace. HELP details can scroll in a short window while Stop stays outside the scroll view; contact controls use minimum heights. |
| `HandsFreeConversationView` | More choices across iPad pages, 96pt minimum tile height and 20pt gutters. Keeps scroll controls for overflow; moving targets reset its local dwell selector. |
| `VoiceBankView` | Adaptive recording-card grid, bounded voice options and page width. Page selection clamps after text-size / size-class changes. |
| `SpeechJournalView`, `TagsView` | Centered, bounded reading and action content. Tags remains unavailable on hardware without NFC. |
| `SettingsView`, its `ShortcutEditorSheet` | Bounded settings and editor width. Shortcut content scrolls with the keyboard or large text. |
| `AddPhraseSheet`, `PersonalInfoEditorSheet` | Bounded form and preview width; existing adaptive 44pt icon / color targets retained. |
| `CheckInDetailSheet`, `SuggestionExplainerSheet` | Bounded reading width in sheets. |
| `VoiceSetupView`, `PersonalVoiceSetupCard` | Bounded setup content; secondary Personal Voice action now has a 44pt minimum height. |
| `PartnerListenView`, `PartnerDisplayView` | Adaptive reply columns; bounded partner-message measure while preserving large, scrollable text and 180-degree flip. |
| `EyeGazeTutorialSheet`, `UndoBar`, `SentencePolishBar` | Bounded guide and undo banner; sentence-error OK target now at least 44×44pt. |
| `RootView`, new `TabBarGazeTargets` | Dwell targets use actual native tab-control frames, including centered tablet bars. Covered / unidentifiable bars register no targets. Touch uses the same system tab bar. |
| `GazeCalibrationView`, `GazeAccuracyCheck`, `GazeSignalCheckView` | Calibration instructions follow window proportions. Six-tile selection check becomes 3×2 in wide landscape. Changing size or orientation cancels a running setup / check rather than mixing coordinate systems. Diagnostic reading width is bounded. |

`AdaptiveLayout.swift` supplies regular-width content limits; `BoardLayout.swift`
keeps pagination consistent with adaptive grid columns. `EyeGazeManager` still
maps normalized coordinates into the current window's safe area, and now clears
filters and dwell progress when that area or orientation changes.

Already suitable, retained: `OnboardingView` (620pt cap and scrolling),
`RecordPhraseStudioSheet` (700pt cap and scrolling), `MessageComposer` (system
sheet), and the parent-sized `BearMascotView`, `LiveWaveformView`,
`HandsFreeStatusViews`, `GazeSelectable`, and `GazeDiagnosticsOverlay` components.
Existing EchoFont Dynamic Type scaling and VoiceOver labels/actions remain.
`Info.plist` already lists all four iPad orientations; the project and plist
required no changes.

## Verification

- Simulator build: **BUILD SUCCEEDED**, exit 0, using the requested `xcodebuild`
  command with a temporary host-only `XCODE_XCCONFIG_FILE` adding
  `OTHER_SWIFT_FLAGS = $(inherited) -disable-sandbox`. The plain invocation fails
  because this host denies Swift macro subprocess sandbox creation
  (`sandbox_apply: Operation not permitted`). No project settings were changed.
- `Scripts/run_tests.sh`: **18 passed, 0 failed**, with the same temporary Swift
  macro flag. Added adaptive-width regression coverage and expanded gaze
  coordinate round trips to 11/13-inch portrait/landscape and multitasking areas.
- Fresh visual verification was unavailable: CoreSimulatorService access is
  denied by this environment. Committed screenshots predate the current tab-bar
  implementation and were used only as visual context.

## Real iPad checks still required

- On 11-inch and 13-inch iPads: every tab, sheet, and cover in all four
  orientations; Split View at narrow / half / wide widths, Slide Over, and live
  resizing. Compare a phone at default text size for layout regressions.
- Default and largest Dynamic Type / app text settings, high contrast,
  VoiceOver and Switch Control; long custom phrases and Spanish labels.
- Mounted TrueDepth hardware: calibrate in each orientation, reach edge tiles,
  dwell on every native tab, pause / resume, blink-page / HELP / Stop, and move
  or resize during calibration. Repeat setup after changing mount or window.
  Confirm UIKit exposes tab controls on the deployed iPadOS version.
- Test keyboard appearance / dismissal in Type and editors, partner flip,
  recording, Personal Voice, backup import/export popovers, and HELP contact
  actions where supported. Head tracking during multitasking needs hardware
  verification because iPadOS may interrupt camera access.
- Re-run the unmodified build command on a Mac without this sandbox restriction.

import SwiftUI

/// Tracking-health readout for hands-free access.
///
/// Hands-free access fails silently: when the face leaves frame or the light
/// drops, the cursor just stops, and the person cannot tell whether the app
/// broke, they drifted out of view, or they are simply aiming badly. This makes
/// the state legible — face acquired or lost, how fast anchors are arriving,
/// what the dwell timer is doing, and whether the blink HELP gesture is armed.
///
/// It is off by default and lives behind a Settings toggle. During daily
/// communication the board should be phrases, not instrumentation; this is for
/// setting up a mount, for a supporter checking why selection is unreliable, and
/// for showing that the tracking is real rather than a drawn circle.
struct GazeDiagnosticsOverlay: View {
    let manager: EyeGazeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(manager.isFaceTracked ? Palette.lime : Palette.red)
                    .frame(width: 8, height: 8)
                Text(manager.isFaceTracked ? String(localized: "Face tracked") : String(localized: "Face lost"))
                    .font(EchoFont.body(12, weight: .bold))
                    .foregroundStyle(Palette.cream)
            }

            if manager.isFaceTracked {
                metric(String(localized: "rate"), String(format: "%.0f Hz", manager.trackingHz))
                metric(String(localized: "mode"), String(localized: "head motion"))
                metric(String(localized: "signal"), manager.activeSource.label)
                metric(String(localized: "mapping"), manager.calibrationInUse == nil ? String(localized: "default") : String(localized: "calibrated"))
                if let cursor = manager.normalizedCursor {
                    metric(String(localized: "cursor"), String(format: "%.2f, %.2f", cursor.x, cursor.y))
                }
                metric(String(localized: "distance"), String(format: "%.0f cm", manager.faceDistance * 100))
                metric(String(localized: "state"), stateLabel)
                metric(String(localized: "dwell"), String(format: "%.0f%%", manager.dwellProgress * 100))
                blinkMeter
                if manager.isEmergencyBlinkArmed {
                    metric(String(localized: "HELP"), String(localized: "hold eyes closed"))
                }
                if manager.blinksInEmergencyWindow > 0 {
                    metric(String(localized: "arm blinks"), String(localized: "%@ of 5", defaultValue: "\(String(describing: manager.blinksInEmergencyWindow)) of 5"))
                }
            } else {
                Text(String(localized: "Move back into the front camera's view."))
                    .font(EchoFont.body(11))
                    .foregroundStyle(Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 150, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.forest.opacity(0.92), in: .rect(cornerRadius: 14))
        .allowsHitTesting(false)
        // One combined element: a live-updating stack of separate labels would
        // interrupt VoiceOver constantly for someone who is not using gaze.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Tracking diagnostics"))
        .accessibilityValue(
            manager.isFaceTracked
                ? String(localized: "Face tracked at %@ hertz", defaultValue: "Face tracked at \(String(describing: Int(manager.trackingHz.rounded()))) hertz")
                : String(localized: "Face not tracked")
        )
    }

    private var stateLabel: String {
        switch manager.selectionState {
        case .tracking: return manager.isSelectionReady ? String(localized: "selecting") : String(localized: "needs setup")
        case .eyesClosed: return String(localized: "eyes closed")
        case .lost: return String(localized: "no signal")
        }
    }

    private func metric(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(EchoFont.body(11))
                .foregroundStyle(Palette.cream.opacity(0.7))
            Spacer(minLength: 8)
            Text(value)
                .font(EchoFont.body(11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.cream)
        }
        .frame(width: 150)
    }

    /// Live eye-closure level. The rule marks the 0.60 threshold the blink
    /// detector fires at, so someone can see how deliberate a blink has to be
    /// before it counts.
    private var blinkMeter: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(String(localized: "eyes"))
                    .font(EchoFont.body(11))
                    .foregroundStyle(Palette.cream.opacity(0.7))
                Spacer(minLength: 8)
                Text(manager.blinkLevel > 0.6 ? String(localized: "closed") : String(localized: "open"))
                    .font(EchoFont.body(11, weight: .bold))
                    .foregroundStyle(Palette.cream)
            }
            .frame(width: 150)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.cream.opacity(0.22))
                    .frame(width: 150, height: 5)
                Capsule()
                    .fill(manager.blinkLevel > 0.6 ? Palette.orange : Palette.lime)
                    .frame(width: max(2, 150 * manager.blinkLevel), height: 5)
                Rectangle()
                    .fill(Palette.cream.opacity(0.7))
                    .frame(width: 1, height: 9)
                    .offset(x: 150 * 0.6)
            }
        }
    }
}

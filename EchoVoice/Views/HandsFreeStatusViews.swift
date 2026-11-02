import SwiftUI

/// The dwell timer drawn around a hovered tile's symbol.
///
/// Its own view so reading `dwellProgress` — which changes every frame while
/// a target is held — redraws only the ring, not the board around it.
struct DwellRing: View {
    @Environment(EyeGazeManager.self) private var eyeGaze
    let diameter: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: eyeGaze.dwellProgress)
            .stroke(Palette.gazeHighlight, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(-90))
            .accessibilityHidden(true)
    }
}

/// A plain-language line saying whether hands-free control can see the
/// person and is ready, shown in the navigation bar so it never moves the
/// board.
struct HandsFreeStatusPill: View {
    @Environment(EyeGazeManager.self) private var eyeGaze

    private var status: (text: String, color: Color) {
        if eyeGaze.sessionFailed { return (String(localized: "Camera unavailable"), Palette.red) }
        if eyeGaze.needsCalibration { return (String(localized: "Setup needed"), Palette.orange) }
        switch eyeGaze.trackingQuality {
        case .off: return (String(localized: "Hands-free off"), Palette.faint)
        case .searching: return (String(localized: "Looking for your face"), Palette.red)
        case .poor:
            if eyeGaze.faceDistance > 0.85 { return (String(localized: "Move a little closer"), Palette.orange) }
            if eyeGaze.faceDistance > 0 && eyeGaze.faceDistance < 0.18 { return (String(localized: "Move a little back"), Palette.orange) }
            return (String(localized: "Tracking is weak"), Palette.orange)
        case .good:
            return (String(localized: "Head control on"), Palette.lime)
        }
    }

    var body: some View {
        let status = status
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 9, height: 9)
            Text(status.text)
                .font(EchoFont.body(14, weight: .bold))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.surface.opacity(0.9), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Hands-free status"))
        .accessibilityValue(status.text)
    }
}

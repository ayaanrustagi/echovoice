import SwiftUI

/// Makes any control reachable by dwell selection.
///
/// Registers the view's on-screen frame with `EyeGazeManager`, which runs one
/// target-aware selector over every registered control (snapping, hysteresis,
/// one selection per visit — see `DwellSelector`). Every control the board
/// exposes to touch has to carry this, or hands-free access silently becomes
/// a smaller app than the one everyone else uses.
///
/// Registration follows the view: it is added when the control appears or
/// moves, and removed when it disappears, is disabled, or is covered (see
/// `gazeSelectionEnabled`). A control that is not on screen can never be
/// selected by a cursor that happens to rest where it used to be.
struct GazeSelectableModifier: ViewModifier {
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.gazeSelectionEnabled) private var selectionEnabled
    @State private var token = UUID()
    @State private var frame: CGRect = .null

    let id: String
    let kind: DwellTarget.Kind
    let isEnabled: Bool
    let showsHighlight: Bool
    let action: () -> Void

    private var isAvailable: Bool {
        eyeGaze.isHandsFreeActive && selectionEnabled && isEnabled
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if showsHighlight && isAvailable && eyeGaze.hoveredTargetID == id {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(kind == .emergency ? Color.white : Palette.gazeHighlight, lineWidth: 3.5)
                        .allowsHitTesting(false)
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                frame = newFrame
                register()
            }
            .onChange(of: isAvailable) { register() }
            .onChange(of: id) { oldID, _ in
                eyeGaze.unregisterTarget(id: oldID, token: token)
                register()
            }
            .onAppear { register() }
            .onDisappear { eyeGaze.unregisterTarget(id: id, token: token) }
    }

    private func register() {
        guard isAvailable, !frame.isNull, frame.width > 1, frame.height > 1 else {
            eyeGaze.unregisterTarget(id: id, token: token)
            return
        }
        eyeGaze.registerTarget(id: id, token: token, frame: frame, kind: kind, action: action)
    }
}

extension View {
    /// Register this control for dwell selection under a stable `id`.
    ///
    /// - Parameters:
    ///   - kind: `.emergency` for HELP: a longer dwell, no snapping.
    ///   - isEnabled: pass the same condition as `.disabled(_:)`. A modifier
    ///     applied outside `.disabled` cannot see it through the environment.
    ///   - showsHighlight: false when the view draws its own hover state.
    func gazeSelectable(
        id: String,
        kind: DwellTarget.Kind = .standard,
        isEnabled: Bool = true,
        showsHighlight: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(GazeSelectableModifier(id: id, kind: kind, isEnabled: isEnabled, showsHighlight: showsHighlight, action: action))
    }
}

private struct GazeSelectionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False for a subtree that is on screen but covered — by a sheet, a
    /// full-screen cover, or the hands-free conversation surface — so its
    /// controls drop out of dwell selection.
    var gazeSelectionEnabled: Bool {
        get { self[GazeSelectionEnabledKey.self] }
        set { self[GazeSelectionEnabledKey.self] = newValue }
    }
}

/// The cursor, its dwell ring, and (optionally) the tracking readout.
///
/// A separate view so that only it re-renders at camera frame rate; when the
/// board read the cursor directly, the whole board redrew sixty times a second.
struct GazeCursorOverlay: View {
    @Environment(EyeGazeManager.self) private var eyeGaze

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let local = CGPoint(x: eyeGaze.cursorPosition.x - origin.x, y: eyeGaze.cursorPosition.y - origin.y)
            ZStack {
                if eyeGaze.isFaceTracked && eyeGaze.normalizedCursor != nil {
                    let paused = eyeGaze.selectionState == .eyesClosed || !eyeGaze.isSelectionReady
                    Circle()
                        .fill(Palette.gazeHighlight.opacity(paused ? 0.10 : 0.25))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Palette.gazeHighlight.opacity(paused ? 0.5 : 1), lineWidth: 2.5))
                        .position(local)

                    if eyeGaze.dwellProgress > 0 {
                        // The filling ring is the dwell timer itself. Showing it
                        // means a selection is never a surprise: looking away
                        // before it closes is how a dwell is undone.
                        Circle()
                            .trim(from: 0, to: eyeGaze.dwellProgress)
                            .stroke(Palette.forest, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(-90))
                            .position(local)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

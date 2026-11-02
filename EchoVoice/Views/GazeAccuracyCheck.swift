import SwiftUI

/// "Try selecting": six rounds on a board-sized grid, using the same
/// `DwellSelector` as the board.
///
/// Each round lights one tile. What is measured is what matters on the
/// board: whether the lit tile gets selected, how long it takes, how often a
/// neighbour is selected instead, how much the cursor wanders while held,
/// and how often tracking drops out.
struct GazeAccuracyCheck: View {
    @Environment(EyeGazeManager.self) private var eyeGaze
    @Environment(\.horizontalSizeClass) private var sizeClass

    let onFinish: (GazeAccuracyResult) -> Void
    let onCancel: () -> Void

    /// Tile order for the six rounds: corners and middles, never the same
    /// tile twice in a row.
    private static let sequence = [0, 5, 2, 3, 4, 1]
    private static let roundTimeout: TimeInterval = 8
    private var columns: Int { sizeClass == .regular && areaSize.width > areaSize.height ? 3 : 2 }
    private var rows: Int { 6 / columns }
    @State private var areaSize: CGSize = .zero

    @State private var round = 0
    @State private var frames: [Int: CGRect] = [:]
    @State private var selector = DwellSelector()
    @State private var flash: (index: Int, correct: Bool)?

    private var targetIndex: Int { Self.sequence[min(round, Self.sequence.count - 1)] }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(eyeGaze.trackingMode == .headMotion ? String(localized: "Point at the green tile") : String(localized: "Look at the green tile"))
                    .font(EchoFont.display(24, weight: .extraBold))
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)
                Text(String(localized: "Hold until it is chosen. Round %@ of %@", defaultValue: "Hold until it is chosen. Round \(String(describing: min(round + 1, Self.sequence.count))) of \(String(describing: Self.sequence.count))"))
                    .font(EchoFont.body(16, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.top, 12)

            Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            tile(row * columns + column)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)

            Button(String(localized: "Stop")) { onCancel() }
                .font(EchoFont.body(17, weight: .bold))
                .foregroundStyle(Palette.controlAccent)
                .frame(minWidth: 88, minHeight: 50)
        }
        .padding(.bottom, 12)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { areaSize = $0 }
        .task { await run() }
        .onDisappear { eyeGaze.debugAimPoint = nil }
    }

    private func tile(_ index: Int) -> some View {
        let isTarget = index == targetIndex && round < Self.sequence.count
        let isHovered = selector.hoveredID == "\(index)"
        let flashColor: Color? = flash.flatMap { $0.index == index ? ($0.correct ? Palette.lime : Palette.red) : nil }
        return RoundedRectangle(cornerRadius: 24)
            .fill(flashColor ?? (isTarget ? Palette.lime : Palette.surface))
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.orange, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: selector.progress)
                        .stroke(Palette.forest, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(minHeight: 110)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[index] = $0 }
            .accessibilityLabel(isTarget ? String(localized: "Target tile") : String(localized: "Tile"))
    }

    @MainActor
    private func run() async {
        var trials: [GazeAccuracyTrial] = []
        for current in 0..<Self.sequence.count {
            round = current
            selector.reset(time: ProcessInfo.processInfo.systemUptime)
            let target = Self.sequence[current]
            let started = ProcessInfo.processInfo.systemUptime
            var samples: [CGPoint] = []
            var wrong = 0
            var losses = 0
            var wasLost = false
            var succeeded = false
            var finished: TimeInterval = Self.roundTimeout

            while ProcessInfo.processInfo.systemUptime - started < Self.roundTimeout {
                let now = ProcessInfo.processInfo.systemUptime
                if let frame = frames[target] {
                    eyeGaze.debugAimPoint = GazeScreenMapping.normalizedPoint(
                        forWindow: CGPoint(x: frame.midX, y: frame.midY), in: eyeGaze.gazeArea)
                }
                let targets = frames.map { DwellTarget(id: "\($0.key)", frame: $0.value) }
                let state: GazeTrackingState = eyeGaze.isSelectionReady ? eyeGaze.selectionState : .lost
                let isLost = state == .lost
                if isLost && !wasLost { losses += 1 }
                wasLost = isLost
                if !isLost, let normalized = eyeGaze.normalizedCursor { samples.append(normalized) }

                if let chosen = selector.update(cursor: isLost ? nil : eyeGaze.cursorPosition, state: state,
                                                targets: targets, time: now, dwellDuration: eyeGaze.dwellDuration),
                   let index = Int(chosen) {
                    flash = (index, index == target)
                    if index == target {
                        succeeded = true
                        finished = now - started
                        break
                    }
                    wrong += 1
                }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }

            let targetPoint = frames[target].map {
                GazeScreenMapping.normalizedPoint(forWindow: CGPoint(x: $0.midX, y: $0.midY), in: eyeGaze.gazeArea)
            } ?? CGPoint(x: 0.5, y: 0.5)
            trials.append(GazeAccuracyTrial(
                target: targetPoint, samples: samples, duration: finished, succeeded: succeeded,
                wrongSelections: wrong, trackingLosses: losses
            ))
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            flash = nil
        }
        eyeGaze.debugAimPoint = nil
        onFinish(GazeAccuracyResult(trackingMode: eyeGaze.trackingMode.rawValue, trials: trials))
    }
}

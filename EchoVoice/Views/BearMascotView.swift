import SwiftUI

/// The app-icon bear, drawn and animated in code so it stays sharp at any size.
///
/// The app's one mascot. It animates only where nobody is aiming at targets;
/// near live gaze targets it is drawn still (`animated: false`), and it never
/// sits among the board's phrase tiles.
/// The same poses render the CAC video clips (`cac-video/mascot/render_mascot.swift`).
struct BearMascotView: View {
    enum Mood: Hashable { case idle, wave, listening, speaking, proud }
    /// `.onDark` swaps to a cream head with a green face so the bear sits
    /// directly on dark surfaces without a backing disc. `.automatic` picks it
    /// in dark mode (and High Contrast), where a dark-green head would vanish.
    enum Style { case automatic, standard, onDark }

    let mood: Mood
    var style: Style = .automatic
    /// Off where gaze targets are live: a moving shape there competes with the cursor.
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = Date()

    var body: some View {
        let still = reduceMotion || !animated
        TimelineView(.animation(paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                BearDrawing.draw(BearPose.make(mood, t: t, still: still), in: &ctx, size: size,
                                 palette: usesLightBear ? .onDark : .standard)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: mood) { start = Date() }   // one-shot moods replay when they begin
        .accessibilityHidden(true)               // decorative; each screen already says what's happening
    }

    private var usesLightBear: Bool {
        switch style {
        case .onDark: return true
        case .standard: return false
        case .automatic: return colorScheme == .dark
        }
    }
}

// MARK: - Pose

struct BearPose {
    var x = 0.0, y = 0.0, rotation = 0.0, scale = 1.0, squash = 0.0
    var earLift = 0.0
    var eyeOpen = 1.0, pupilX = 0.0, pupilY = 0.0
    var happyEyes = false
    var smile = 1.0
    var mouthOpen: Double? = nil
    var bars = 0.0, barPhase = 0.0
    var sparkle = -1.0
    var wave: Double? = nil            // hand angle in degrees; nil hides the hand
    var handScale = 0.0

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
    private static func easeOutBack(_ v: Double) -> Double {
        let v = clamp(v), c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(v - 1, 3) + c1 * pow(v - 1, 2)
    }
    /// Openness 0...1 for a short blink repeating every `period` seconds.
    private static func blink(_ t: Double, period: Double, at: Double) -> Double {
        let d = abs(t.truncatingRemainder(dividingBy: period) - at) / 0.08
        return min(d, 1)
    }

    static func make(_ mood: BearMascotView.Mood, t: Double, still: Bool) -> BearPose {
        var p = BearPose()
        switch mood {
        case .idle:
            guard !still else { return p }
            p.y = -8 * (0.5 - 0.5 * cos(t / 1.5 * 2 * .pi))
            p.eyeOpen = blink(t, period: 3.6, at: 2.4)

        case .wave:
            p.smile = 1.25
            guard !still else { p.wave = 30; p.handScale = 1.6; return p }
            // Pop in, wave three times, then settle into idle with the hand lowered.
            let grow = seg(t, 0, 0.45)
            p.scale = grow <= 0 ? 0.001 : easeOutBack(grow)
            p.squash = 0.12 * sin(seg(t, 0.4, 0.75) * .pi)
            let handIn = easeOutBack(seg(t, 0.5, 0.8))
            let handOut = 1 - seg(t, 2.3, 2.6)
            p.handScale = 1.6 * handIn * handOut
            p.wave = 20 + 28 * sin(seg(t, 0.7, 2.3) * 3 * 2 * .pi)
            p.y = t > 2.6 ? -8 * (0.5 - 0.5 * cos((t - 2.6) / 1.5 * 2 * .pi)) : 0
            p.eyeOpen = blink(t, period: 3.6, at: 3.1)

        case .listening:
            p.rotation = -7; p.pupilX = 10; p.pupilY = -6; p.smile = 0.5
            p.bars = 1; p.earLift = -18
            guard !still else { p.barPhase = 0.3; return p }
            p.earLift = -18 - 6 * sin(t / 1.5 * 2 * .pi)
            p.barPhase = t / 0.75
            p.eyeOpen = blink(t, period: 3.6, at: 2.2)

        case .speaking:
            p.bars = 0.8
            guard !still else { p.mouthOpen = 40; return p }
            let talk = abs(sin(t * 7.3)) * (0.6 + 0.4 * abs(sin(t * 2.1)))
            p.mouthOpen = 14 + 46 * talk
            p.y = -6 * talk
            p.barPhase = t / 0.5
            p.eyeOpen = blink(t, period: 3.2, at: 1.4)

        case .proud:
            p.happyEyes = true; p.smile = 1.25
            guard !still else { return p }
            let hop = sin(seg(t, 0.1, 0.55) * .pi), hop2 = sin(seg(t, 0.6, 0.95) * .pi) * 0.5
            p.y = -60 * (hop + hop2)
            p.squash = -0.08 * (hop + hop2) + 0.1 * sin(seg(t, 0.5, 0.65) * .pi)
            p.earLift = -20 * (hop + hop2)
            p.sparkle = seg(t, 0.2, 1.6)
        }
        return p
    }
}

// MARK: - Drawing (1080-point design space, pivot at the bottom-center of the head)

enum BearDrawing {
    static let lime = Color(red: 168 / 255, green: 214 / 255, blue: 58 / 255)
    static let green = Color(red: 30 / 255, green: 77 / 255, blue: 46 / 255)
    static let cream = Color(red: 249 / 255, green: 246 / 255, blue: 239 / 255)
    static let mouthInside = Color(red: 14 / 255, green: 40 / 255, blue: 24 / 255)

    struct Palette {
        var head: Color, face: Color, pupil: Color, mouthInside: Color, shadow: Bool
        static let standard = Palette(head: green, face: cream, pupil: green, mouthInside: BearDrawing.mouthInside, shadow: true)
        static let onDark = Palette(head: cream, face: green, pupil: cream, mouthInside: lime, shadow: false)
    }

    private static func dot(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    static func draw(_ p: BearPose, in ctx: inout GraphicsContext, size: CGSize, palette: Palette = .standard) {
        let s = min(size.width, size.height) / 1080
        ctx.translateBy(x: (size.width - 1080 * s) / 2, y: (size.height - 1080 * s) / 2)
        ctx.scaleBy(x: s, y: s)

        if palette.shadow {
            let lift = min(max(0, -p.y), 200)
            let sw = 380 * p.scale * (1 - lift / 400)
            ctx.fill(Path(ellipseIn: CGRect(x: 540 + p.x - sw / 2, y: 862, width: sw, height: 36)),
                     with: .color(.black.opacity(0.14 * (1 - lift / 300))))
        }

        ctx.translateBy(x: 540 + p.x, y: 870 + p.y)
        ctx.rotate(by: .degrees(p.rotation))
        ctx.scaleBy(x: p.scale * (1 + p.squash), y: p.scale * (1 - p.squash))

        drawBars(p, &ctx)
        for side in [-1.0, 1.0] { ctx.fill(dot(180 * side, -400 + p.earLift, 100), with: .color(lime)) }
        ctx.fill(Path(ellipseIn: CGRect(x: -220, y: -380, width: 440, height: 380)), with: .color(palette.head))
        for cx in [-80.0, 80.0] { drawEye(p, cx, palette, &ctx) }
        drawMouth(p, palette, &ctx)
        drawSparkles(p, &ctx)
        drawHand(p, palette, &ctx)
    }

    private static func drawEye(_ p: BearPose, _ cx: Double, _ palette: Palette, _ ctx: inout GraphicsContext) {
        let cy = -230.0, r = 40.0
        if p.happyEyes {
            var arc = Path()
            arc.move(to: CGPoint(x: cx - 30, y: cy + 8))
            arc.addQuadCurve(to: CGPoint(x: cx + 30, y: cy + 8), control: CGPoint(x: cx, y: cy - 34))
            ctx.stroke(arc, with: .color(palette.face), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            return
        }
        let h = r * max(p.eyeOpen, 0.08)
        let eye = Path(ellipseIn: CGRect(x: cx - r, y: cy - h, width: r * 2, height: h * 2))
        ctx.fill(eye, with: .color(palette.face))
        var inner = ctx
        inner.clip(to: eye)
        inner.fill(dot(cx + p.pupilX, cy + p.pupilY, 15), with: .color(palette.pupil))
    }

    private static func drawMouth(_ p: BearPose, _ palette: Palette, _ ctx: inout GraphicsContext) {
        if let open = p.mouthOpen {
            let w = 96.0, h = max(open, 10)
            ctx.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -150 - h / 2, width: w, height: h)), with: .color(palette.face))
            if h > 22 {
                ctx.fill(Path(ellipseIn: CGRect(x: -w / 2 + 12, y: -150 - h / 2 + 9, width: w - 24, height: h - 18)),
                         with: .color(palette.mouthInside))
            }
            return
        }
        var smile = Path()
        smile.move(to: CGPoint(x: -64, y: -142))
        smile.addQuadCurve(to: CGPoint(x: 64, y: -142), control: CGPoint(x: 0, y: -142 + 52 * p.smile))
        ctx.stroke(smile, with: .color(palette.face), style: StrokeStyle(lineWidth: 24, lineCap: .round))
    }

    private static func drawBars(_ p: BearPose, _ ctx: inout GraphicsContext) {
        guard p.bars > 0 else { return }
        for side in [-1.0, 1.0] {
            for i in 0..<3 {
                let wave = 0.5 + 0.5 * sin(p.barPhase * 2 * .pi + Double(i) * 1.3 + (side > 0 ? 0.7 : 0))
                let h = (40 + 90 * wave * (i == 1 ? 1 : 0.7)) * p.bars
                let x = side * (290 + Double(i) * 40)
                ctx.fill(Path(roundedRect: CGRect(x: x - 10, y: -200 - h / 2, width: 20, height: h), cornerRadius: 10),
                         with: .color(lime.opacity(p.bars)))
            }
        }
    }

    private static func drawSparkles(_ p: BearPose, _ ctx: inout GraphicsContext) {
        guard p.sparkle >= 0 else { return }
        let spots: [(Double, Double, Double)] = [(-300, -420, 0), (290, -470, 0.15), (330, -250, 0.3), (-330, -230, 0.22)]
        for (x, y, delay) in spots {
            let t = min(max((p.sparkle - delay) / 0.6, 0), 1)
            guard t > 0, t < 1 else { continue }
            let r = sin(t * .pi) * 34, c = CGPoint(x: x, y: y)
            var star = Path()
            star.move(to: CGPoint(x: x, y: y - r))
            star.addQuadCurve(to: CGPoint(x: x + r, y: y), control: c)
            star.addQuadCurve(to: CGPoint(x: x, y: y + r), control: c)
            star.addQuadCurve(to: CGPoint(x: x - r, y: y), control: c)
            star.addQuadCurve(to: CGPoint(x: x, y: y - r), control: c)
            ctx.fill(star, with: .color(lime.opacity(sin(t * .pi))))
        }
    }

    private static func drawHand(_ p: BearPose, _ palette: Palette, _ ctx: inout GraphicsContext) {
        guard let angle = p.wave, p.handScale > 0.01 else { return }
        var hand = ctx
        hand.translateBy(x: 380, y: -150)
        hand.rotate(by: .degrees(angle))
        hand.scaleBy(x: p.handScale, y: p.handScale)
        let palm = Path(ellipseIn: CGRect(x: -46, y: -150, width: 92, height: 100))
        let thumb = Path(ellipseIn: CGRect(x: -74, y: -112, width: 44, height: 44))
        // Outline first, then fill, so the thumb and palm read as one mitten.
        for part in [thumb, palm] { hand.stroke(part, with: .color(palette.head == green ? green : mouthInside), lineWidth: 10) }
        for part in [thumb, palm] { hand.fill(part, with: .color(lime)) }
    }
}

#Preview {
    HStack {
        ForEach([BearMascotView.Mood.wave, .listening, .speaking, .proud], id: \.self) { mood in
            BearMascotView(mood: mood).frame(width: 90)
        }
    }
    .padding()
}


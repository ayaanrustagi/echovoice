import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Design tokens carried over from the EchoVoice web build so the two look like
/// one product. Warm, high-contrast, dignified — never childish.
enum Palette {
    /// Dwell hover and the gaze cursor. Deliberately not adaptive: the
    /// adaptive orange darkens to a dull brown in high contrast, where a
    /// hovered target has to be the brightest thing on screen.
    static let gazeHighlight = Color(red: 1.0, green: 0.70, blue: 0.16)

    #if os(iOS)
    // The original visual tokens are adaptive too. A number of older screens
    // still use these names directly, so making them trait-aware prevents any
    // page or sheet from silently falling back to the light appearance.
    static let cream = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.020, green: 0.055, blue: 0.033, alpha: 1)
            : UIColor(red: 0.980, green: 0.969, blue: 0.941, alpha: 1)
    })
    static let canvas = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.032, green: 0.082, blue: 0.050, alpha: 1)
            : UIColor(red: 0.941, green: 0.925, blue: 0.886, alpha: 1)
    })
    static let forest = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.952, green: 0.945, blue: 0.906, alpha: 1)
            : UIColor(red: 0.118, green: 0.302, blue: 0.169, alpha: 1)
    })
    static let forestMid = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.820, green: 0.880, blue: 0.835, alpha: 1)
            : UIColor(red: 0.180, green: 0.361, blue: 0.227, alpha: 1)
    })
    static let lime = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.310, green: 0.420, blue: 0.282, alpha: 1)
            : UIColor(red: 0.659, green: 0.831, blue: 0.216, alpha: 1)
    })
    static let orange = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.482, green: 0.345, blue: 0.204, alpha: 1)
            : UIColor(red: 0.957, green: 0.639, blue: 0.251, alpha: 1)
    })
    static let sky = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.271, green: 0.380, blue: 0.416, alpha: 1)
            : UIColor(red: 0.486, green: 0.792, blue: 0.910, alpha: 1)
    })
    static let lavender = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.369, green: 0.333, blue: 0.416, alpha: 1)
            : UIColor(red: 0.745, green: 0.667, blue: 0.918, alpha: 1)
    })
    static let rose = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.420, green: 0.282, blue: 0.329, alpha: 1)
            : UIColor(red: 0.949, green: 0.620, blue: 0.710, alpha: 1)
    })
    static let red = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.820, green: 0.260, blue: 0.260, alpha: 1)
            : UIColor(red: 0.839, green: 0.271, blue: 0.271, alpha: 1)
    })
    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.972, green: 0.968, blue: 0.945, alpha: 1)
            : UIColor(red: 0.110, green: 0.110, blue: 0.110, alpha: 1)
    })
    static let muted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.820, green: 0.880, blue: 0.835, alpha: 1)
            : UIColor(red: 0.333, green: 0.322, blue: 0.290, alpha: 1)
    })
    static let faint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.690, green: 0.750, blue: 0.705, alpha: 1)
            // #6B665C: 5.3:1 on cream, so secondary text passes WCAG AA (was #8A8478, 3.5:1).
            : UIColor(red: 0.420, green: 0.400, blue: 0.361, alpha: 1)
    })
    static let faintest = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.570, green: 0.625, blue: 0.585, alpha: 1)
            : UIColor(red: 0.710, green: 0.686, blue: 0.635, alpha: 1)
    })
    #else
    static let cream = Color(red: 0.980, green: 0.969, blue: 0.941)   // #FAF7F0
    static let canvas = Color(red: 0.941, green: 0.925, blue: 0.886)  // #F0ECE2
    static let forest = Color(red: 0.118, green: 0.302, blue: 0.169)  // #1E4D2B
    static let forestMid = Color(red: 0.180, green: 0.361, blue: 0.227) // #2E5C3A
    static let lime = Color(red: 0.659, green: 0.831, blue: 0.216)    // #A8D437
    static let orange = Color(red: 0.957, green: 0.639, blue: 0.251)  // #F4A340
    static let sky = Color(red: 0.486, green: 0.792, blue: 0.910)     // #7CCAE8
    static let lavender = Color(red: 0.745, green: 0.667, blue: 0.918) // #BEAAEA
    static let rose = Color(red: 0.949, green: 0.620, blue: 0.710)    // #F29EB5
    static let red = Color(red: 0.839, green: 0.271, blue: 0.271)     // #D64545
    static let ink = Color(red: 0.110, green: 0.110, blue: 0.110)     // #1C1C1C
    static let muted = Color(red: 0.333, green: 0.322, blue: 0.290)   // #55524A
    static let faint = Color(red: 0.420, green: 0.400, blue: 0.361)   // #6B665C, WCAG AA on cream
    static let faintest = Color(red: 0.710, green: 0.686, blue: 0.635) // #B5AFA2
    #endif

    // Semantic colors adapt when the user enables EchoVoice's high-contrast
    // appearance. The original palette remains available for phrase colors,
    // whose meaning should not change between themes.
    #if os(iOS)
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.020, green: 0.055, blue: 0.033, alpha: 1)
            : UIColor(red: 0.980, green: 0.969, blue: 0.941, alpha: 1)
    })
    static let surface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.135, blue: 0.082, alpha: 1)
            : .white
    })
    static let dockSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.135, blue: 0.082, alpha: 1)
            : UIColor(red: 0.976, green: 0.957, blue: 0.933, alpha: 1)
    })
    static let primaryText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(red: 0.110, green: 0.110, blue: 0.110, alpha: 1)
    })
    static let secondaryText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.820, green: 0.880, blue: 0.835, alpha: 1)
            : UIColor(red: 0.333, green: 0.322, blue: 0.290, alpha: 1)
    })
    static let controlAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.952, green: 0.945, blue: 0.906, alpha: 1)
            : UIColor(red: 0.118, green: 0.302, blue: 0.169, alpha: 1)
    })
    static let onControlAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.020, green: 0.055, blue: 0.033, alpha: 1)
            : UIColor(red: 0.980, green: 0.969, blue: 0.941, alpha: 1)
    })
    #else
    static let background = cream
    static let surface = Color.white
    static let dockSurface = Color(red: 0.976, green: 0.957, blue: 0.933)
    static let primaryText = ink
    static let secondaryText = muted
    static let controlAccent = forest
    static let onControlAccent = cream
    #endif

    // Restrained, flat phrase colors for high contrast. They remain distinct
    // without the fluorescent look of the standard lime/orange palette.
    static let contrastSage = Color(red: 0.310, green: 0.420, blue: 0.282)
    static let contrastAmber = Color(red: 0.482, green: 0.345, blue: 0.204)
    static let contrastBlue = Color(red: 0.271, green: 0.380, blue: 0.416)
    static let contrastPlum = Color(red: 0.369, green: 0.333, blue: 0.416)
    static let contrastRose = Color(red: 0.420, green: 0.282, blue: 0.329)
    static let contrastForest = Color(red: 0.145, green: 0.290, blue: 0.188)
    static let contrastPhraseText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.972, green: 0.968, blue: 0.945, alpha: 1)
            : UIColor(red: 0.118, green: 0.302, blue: 0.169, alpha: 1)
    })
    static let onForestPhrase = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.972, green: 0.968, blue: 0.945, alpha: 1)
            : UIColor(red: 0.980, green: 0.969, blue: 0.941, alpha: 1)
    })
}

/// Shared motion vocabulary, so every screen springs the same way.
///
/// Deliberately fast and low-overshoot. This is an AAC app: someone reaching for
/// a tile with unsteady hands needs it to settle *now*, and a target still
/// wobbling when a finger lands is a target that gets missed. Bounce is used to
/// confirm what already happened, never to delay it.
enum Motion {
    /// Confirmation pop — quick, with just enough spring to confirm the action.
    static let pop = Animation.spring(response: 0.30, dampingFraction: 0.78)
    /// Press/release — quick and near-critically damped.
    static let snap = Animation.spring(response: 0.20, dampingFraction: 0.84)
    /// Entrance of a card or screen.
    static let entrance = Animation.spring(response: 0.36, dampingFraction: 0.82)

    /// Per-item stagger. Kept short so a full board is settled in well under a second.
    static let stagger = 0.035
}

#if os(iOS)
/// Tap feedback. On a board where every press produces speech, haptics confirm
/// the press landed even before audio starts — useful when hearing is also going.
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)

    /// Call on appear so the Taptic Engine is warm and the first tap isn't late.
    static func prepare() { impact.prepare() }

    static func tap() {
        impact.impactOccurred()
        impact.prepare()
    }
}
#else
enum Haptics {
    static func prepare() {}
    static func tap() {}
}
#endif

/// Tactile press feedback for tiles/buttons — mirrors the web app's `.press`
/// class. Scale is skipped under Reduce Motion.
struct Pressable: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed && !reduceMotion ? 0.02 : 0)
            .animation(reduceMotion ? nil : Motion.snap, value: configuration.isPressed)
    }
}

/// Staggered entrance — mirrors the web app's `.fade-up` with `--i` delays,
/// with a slight scale-up so cards arrive rather than just fade.
struct FadeUp: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        let settled = shown || reduceMotion
        return content
            .opacity(settled ? 1 : 0)
            .scaleEffect(settled ? 1 : 0.97)
            .offset(y: settled ? 0 : 10)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.entrance.delay(Double(index) * Motion.stagger)) {
                    shown = true
                }
            }
    }
}

/// Scale + fade entrance for a single element, no stagger.
struct PopIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        let settled = shown || reduceMotion
        return content
            .opacity(settled ? 1 : 0)
            .scaleEffect(settled ? 1 : 0.90)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.pop.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func fadeUp(index: Int) -> some View { modifier(FadeUp(index: index)) }
    func popIn(delay: Double = 0) -> some View { modifier(PopIn(delay: delay)) }
}

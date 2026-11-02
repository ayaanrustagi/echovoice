import CoreText
import SwiftUI

/// The exact typefaces from the EchoVoice web design (Bricolage Grotesque for
/// display/headings, Hanken Grotesk for body), loaded dynamically from bundled TTF resources.
enum EchoFont {
    private static var isRegistered = false

    /// Automatically registers all custom TTF font files into CoreText font registry.
    public static func registerFonts() {
        guard !isRegistered else { return }
        isRegistered = true

        let fontFiles = [
            "BricolageGrotesque-600",
            "BricolageGrotesque-700",
            "BricolageGrotesque-800",
            "HankenGrotesk-400",
            "HankenGrotesk-500",
            "HankenGrotesk-700"
        ]

        for fontName in fontFiles {
            if let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") ??
                         Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    // Text scaling goes through Dynamic Type (`relativeTo:`) rather than a manual
    // multiplier read from UserDefaults.
    //
    // The multiplier version was broken in a subtle way: UserDefaults is not
    // observable by SwiftUI, so changing the setting invalidated nothing. Only
    // views that happened to re-render for some other reason picked up the new
    // size, leaving the screen in a half-resized state. Sizing relative to a text
    // style makes the scale a real environment dependency, so every view updates
    // together — and `@ScaledMetric` values like tile heights grow with the text
    // instead of staying fixed and letting labels overflow.

    /// Bricolage Grotesque — headings, phrase labels, buttons.
    static func display(_ size: CGFloat, weight: Weight = .bold) -> Font {
        registerFonts()
        let fontName = weight.bricolagePostScriptName
        if UIFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size, relativeTo: .title)
        }
        return .system(size: size, weight: weight.systemWeight, design: .rounded)
    }

    /// Hanken Grotesk — body copy, captions.
    static func body(_ size: CGFloat, weight: Weight = .regular) -> Font {
        registerFonts()
        let fontName = weight.hankenPostScriptName
        if UIFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size, relativeTo: .body)
        }
        return .system(size: size, weight: weight.systemWeight, design: .default)
    }

    enum Weight {
        case regular, medium, semibold, bold, extraBold

        var systemWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .extraBold: return .black
            }
        }

        var bricolagePostScriptName: String {
            switch self {
            case .semibold: return "BricolageGrotesque-SemiBold"
            case .extraBold: return "BricolageGrotesque-ExtraBold"
            default: return "BricolageGrotesque-Bold"
            }
        }

        var hankenPostScriptName: String {
            switch self {
            case .medium: return "HankenGrotesk-Medium"
            case .bold, .semibold, .extraBold: return "HankenGrotesk-Bold"
            default: return "HankenGrotesk-Regular"
            }
        }
    }
}

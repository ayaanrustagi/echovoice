import SwiftUI

/// Hand-translated from the original design's inline SVG paths (viewBox 0 0 24
/// 24 unless noted), so the icons are pixel-faithful to the web app rather than
/// approximated with SF Symbols.
enum EchoIcon {
    /// Water drop — Water tile.
    static func drop() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 12, y: 2))
            p.addCurve(to: CGPoint(x: 5, y: 15.5), control1: CGPoint(x: 12, y: 2), control2: CGPoint(x: 5, y: 11))
            p.addCurve(to: CGPoint(x: 12, y: 23), control1: CGPoint(x: 5, y: 19.6), control2: CGPoint(x: 8.4, y: 23))
            p.addCurve(to: CGPoint(x: 19, y: 15.5), control1: CGPoint(x: 15.6, y: 23), control2: CGPoint(x: 19, y: 19.6))
            p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 19, y: 11), control2: CGPoint(x: 12, y: 2))
            p.closeSubpath()
        }
    }

    /// Person figure — Bathroom tile.
    static func figure() -> Path {
        Path { p in
            p.addEllipse(in: CGRect(x: 9, y: 2, width: 6, height: 6))
            p.move(to: CGPoint(x: 6, y: 22))
            p.addLine(to: CGPoint(x: 8, y: 10))
            p.addLine(to: CGPoint(x: 16, y: 10))
            p.addLine(to: CGPoint(x: 18, y: 22))
            p.addLine(to: CGPoint(x: 14.5, y: 22))
            p.addLine(to: CGPoint(x: 13.5, y: 14))
            p.addLine(to: CGPoint(x: 10.5, y: 14))
            p.addLine(to: CGPoint(x: 9.5, y: 22))
            p.closeSubpath()
        }
    }

    /// Lightning bolt (stroked) — Pain tile.
    static func bolt() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 9, y: 3))
            p.addLine(to: CGPoint(x: 11, y: 10))
            p.addLine(to: CGPoint(x: 8, y: 12))
            p.addLine(to: CGPoint(x: 14, y: 21))
        }
    }

    /// Heart — I Love You tile.
    static func heart() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 12, y: 21))
            p.addCurve(to: CGPoint(x: 3, y: 8.8), control1: CGPoint(x: 12, y: 21), control2: CGPoint(x: 3, y: 14.8))
            p.addCurve(to: CGPoint(x: 8.5, y: 3.2), control1: CGPoint(x: 3, y: 5.6), control2: CGPoint(x: 5.5, y: 3.2))
            p.addCurve(to: CGPoint(x: 12, y: 5.1), control1: CGPoint(x: 10.1, y: 3.2), control2: CGPoint(x: 11.4, y: 4))
            p.addCurve(to: CGPoint(x: 15.5, y: 3.2), control1: CGPoint(x: 12.6, y: 4), control2: CGPoint(x: 13.9, y: 3.2))
            p.addCurve(to: CGPoint(x: 21, y: 8.8), control1: CGPoint(x: 18.5, y: 3.2), control2: CGPoint(x: 21, y: 5.6))
            p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 21, y: 14.8), control2: CGPoint(x: 12, y: 21))
            p.closeSubpath()
        }
    }

    /// TV — TV tile.
    static func tv() -> Path {
        Path { p in
            p.addRoundedRect(in: CGRect(x: 2, y: 4, width: 20, height: 13), cornerSize: CGSize(width: 3, height: 3))
            p.addRoundedRect(in: CGRect(x: 9, y: 19, width: 6, height: 2.4), cornerSize: CGSize(width: 1.2, height: 1.2))
        }
    }

    /// Snowflake (three crossing lines, stroked) — Cold tile.
    static func snowflake() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 12, y: 2)); p.addLine(to: CGPoint(x: 12, y: 22))
            p.move(to: CGPoint(x: 4, y: 7)); p.addLine(to: CGPoint(x: 20, y: 17))
            p.move(to: CGPoint(x: 20, y: 7)); p.addLine(to: CGPoint(x: 4, y: 17))
        }
    }

    /// Cross (stroked) — No tile.
    static func xmark() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 6, y: 6)); p.addLine(to: CGPoint(x: 18, y: 18))
            p.move(to: CGPoint(x: 18, y: 6)); p.addLine(to: CGPoint(x: 6, y: 18))
        }
    }

    /// Bowl with steam (stroked) — Hungry tile.
    static func bowl() -> Path {
        Path { p in
            // Bowl: a half-round resting on a base line.
            p.move(to: CGPoint(x: 3, y: 12))
            p.addCurve(to: CGPoint(x: 21, y: 12), control1: CGPoint(x: 3, y: 20), control2: CGPoint(x: 21, y: 20))
            p.closeSubpath()
            // Steam
            p.move(to: CGPoint(x: 9, y: 3)); p.addLine(to: CGPoint(x: 9, y: 7))
            p.move(to: CGPoint(x: 15, y: 3)); p.addLine(to: CGPoint(x: 15, y: 7))
        }
    }

    /// Folded blanket (stroked) — Blanket tile. An outline with the top-left
    /// corner turned down, which reads as folded fabric; stacked bars read as a
    /// sandwich instead.
    static func blanket() -> Path {
        Path { p in
            p.addRoundedRect(in: CGRect(x: 3.5, y: 5, width: 17, height: 14), cornerSize: CGSize(width: 2.5, height: 2.5))
            // Turned-down corner
            p.move(to: CGPoint(x: 3.5, y: 11))
            p.addLine(to: CGPoint(x: 10, y: 11))
            p.addLine(to: CGPoint(x: 10, y: 5))
        }
    }

    /// Upward arrow (stroked) — Sit Me Up tile.
    static func arrowUp() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 12, y: 21)); p.addLine(to: CGPoint(x: 12, y: 4))
            p.move(to: CGPoint(x: 5, y: 11)); p.addLine(to: CGPoint(x: 12, y: 4))
            p.addLine(to: CGPoint(x: 19, y: 11))
        }
    }

    /// Musical note — Music tile.
    static func note() -> Path {
        Path { p in
            p.addEllipse(in: CGRect(x: 4, y: 15.5, width: 6, height: 5))
            p.addEllipse(in: CGRect(x: 14, y: 13.5, width: 6, height: 5))
            // Stems + the bar joining them
            p.move(to: CGPoint(x: 10, y: 18))
            p.addLine(to: CGPoint(x: 10, y: 6))
            p.addLine(to: CGPoint(x: 20, y: 4))
            p.addLine(to: CGPoint(x: 20, y: 16))
            p.closeSubpath()
        }
    }

    /// Speaker + sound waves (stroked accent) — "Speaking…" toast, tab icon.
    static func speaker() -> (fill: Path, stroke: Path) {
        let fill = Path { p in
            p.move(to: CGPoint(x: 4, y: 9)); p.addLine(to: CGPoint(x: 4, y: 15))
            p.addLine(to: CGPoint(x: 8, y: 15)); p.addLine(to: CGPoint(x: 14, y: 20))
            p.addLine(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 8, y: 9))
            p.closeSubpath()
        }
        let stroke = Path { p in
            p.move(to: CGPoint(x: 17, y: 9))
            p.addCurve(to: CGPoint(x: 17, y: 15), control1: CGPoint(x: 18.5, y: 10.5), control2: CGPoint(x: 18.5, y: 13.5))
        }
        return (fill, stroke)
    }

    /// Exclamation-in-circle — HELP button.
    static func exclaim() -> Path {
        Path { p in
            p.addRoundedRect(in: CGRect(x: 10.4, y: 6, width: 3.2, height: 8), cornerSize: CGSize(width: 1.6, height: 1.6))
            p.addEllipse(in: CGRect(x: 10.2, y: 15.7, width: 3.6, height: 3.6))
        }
    }

    /// Checkmark — "I'm Okay" button, dashboard status dot.
    static func check() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 4, y: 12.5))
            p.addLine(to: CGPoint(x: 9.5, y: 18))
            p.addLine(to: CGPoint(x: 20, y: 5))
        }
    }
}

/// A shape helper that scales 24x24 SVG vector paths into any frame rect dead-center.
struct VectorIconShape: Shape {
    let rawPath: Path

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 24.0
        let scaleY = rect.height / 24.0
        return rawPath.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}

/// A phrase-tile icon glyph: fill-based icons use `fillPath`, stroke-based
/// icons (Pain, Cold, TV screen accent) use `strokePath`. Matches the mixed
/// fill/stroke styling of the original SVGs exactly.
struct PhraseGlyph: View {
    let symbol: Phrase.Symbol
    let color: Color

    var body: some View {
        ZStack {
            switch symbol {
            case .water:
                VectorIconShape(rawPath: EchoIcon.drop()).fill(color)
            case .bathroom:
                VectorIconShape(rawPath: EchoIcon.figure()).fill(color)
            case .pain:
                VectorIconShape(rawPath: EchoIcon.bolt()).stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            case .love:
                VectorIconShape(rawPath: EchoIcon.heart()).fill(color)
            case .tv:
                VectorIconShape(rawPath: EchoIcon.tv()).fill(color)
            case .cold:
                VectorIconShape(rawPath: EchoIcon.snowflake()).stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            case .yes:
                VectorIconShape(rawPath: EchoIcon.check()).stroke(color, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
            case .no:
                VectorIconShape(rawPath: EchoIcon.xmark()).stroke(color, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            case .hungry:
                VectorIconShape(rawPath: EchoIcon.bowl()).stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            case .blanket:
                VectorIconShape(rawPath: EchoIcon.blanket()).stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            case .sitUp:
                VectorIconShape(rawPath: EchoIcon.arrowUp()).stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            case .music:
                VectorIconShape(rawPath: EchoIcon.note()).fill(color)
            case .custom:
                let (fill, stroke) = EchoIcon.speaker()
                ZStack {
                    VectorIconShape(rawPath: fill).fill(color)
                    VectorIconShape(rawPath: stroke).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 22, height: 22)
    }
}

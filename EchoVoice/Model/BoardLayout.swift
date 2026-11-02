import Foundation

/// Matches GridItem.adaptive's column calculation, so paged boards show only
/// the choices that fit the current window rather than a device's screen size.
enum BoardLayout {
    static func columnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, minimum.isFinite, spacing.isFinite,
              width > 0, minimum > 0, spacing >= 0 else { return 1 }
        return max(1, Int((width + spacing) / (minimum + spacing)))
    }
}

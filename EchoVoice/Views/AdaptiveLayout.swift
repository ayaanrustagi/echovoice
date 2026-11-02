import SwiftUI

/// Reading and editing screens keep a comfortable measure on iPad. The
/// compact layout stays full width, including Split View and Slide Over.
private struct ReadableContentWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? width : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableContentWidth(_ width: CGFloat = 720) -> some View {
        modifier(ReadableContentWidth(width: width))
    }
}

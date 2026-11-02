import Foundation

@main
enum BoardLayoutSmoke {
    static func main() {
        // Slide Over, Split View, and 11/13-inch portrait and landscape
        // content widths after the board's 16pt margins.
        let widths: [CGFloat] = [288, 568, 788, 802, 992, 1162, 1334]
        let expected = [1, 3, 4, 4, 5, 6, 6]
        for (width, count) in zip(widths, expected) {
            precondition(BoardLayout.columnCount(width: width, minimum: 180, spacing: 14) == count)
            for minimum: CGFloat in [120, 180, 240, 360, 540] {
                let columns = BoardLayout.columnCount(width: width, minimum: minimum, spacing: 20)
                // Nothing clips horizontally, even with scaled text or large
                // dwell targets. Another column would have to shrink a tile.
                if width >= minimum {
                    precondition(CGFloat(columns) * minimum + CGFloat(columns - 1) * 20 <= width)
                }
                precondition(CGFloat(columns + 1) * minimum + CGFloat(columns) * 20 > width)
            }
        }
        precondition(BoardLayout.columnCount(width: 567, minimum: 180, spacing: 14) == 2)
        precondition(BoardLayout.columnCount(width: 568, minimum: 180, spacing: 14) == 3)
        precondition(BoardLayout.columnCount(width: 1334, minimum: 240, spacing: 20) == 5)
        precondition(BoardLayout.columnCount(width: 1334, minimum: 120, spacing: 8) == 10)
        precondition(BoardLayout.columnCount(width: 0, minimum: 180, spacing: 14) == 1)
        precondition(BoardLayout.columnCount(width: .infinity, minimum: 180, spacing: 14) == 1)
        print("Adaptive board layout smoke tests passed")
    }
}

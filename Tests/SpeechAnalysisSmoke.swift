import Foundation

@main
struct SpeechAnalysisSmoke {
    private static let sampleRate = 16_000.0

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(sampleRate * seconds))
    }

    private static func tone(_ seconds: Double, frequency: Double = 180) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { index in
            Float(0.3 * sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
    }

    static func main() {
        let edgeTrimmed = SpeechAnalysis.analyze(
            samples: silence(0.4) + tone(2) + silence(0.4),
            sampleRate: sampleRate,
            wordCount: 4
        )
        precondition((115...122).contains(edgeTrimmed.wpm), "edge silence changed speaking rate")
        precondition(edgeTrimmed.pauseRatio < 0.03, "edge silence counted as an internal pause")

        let withPause = SpeechAnalysis.analyze(
            samples: tone(1) + silence(0.5) + tone(1),
            sampleRate: sampleRate,
            wordCount: 5
        )
        precondition((115...122).contains(withPause.wpm), "speaking rate must include internal pauses")
        precondition((0.17...0.22).contains(withPause.pauseRatio), "internal pause ratio is wrong")
        precondition(withPause.articulationRate > withPause.wpm, "articulation rate must exclude pauses")

        let empty = SpeechAnalysis.analyze(samples: silence(1), sampleRate: sampleRate, wordCount: 4)
        precondition(empty.wpm == 0 && empty.pauseRatio == 1, "silence must not become a reading")

        print("SpeechAnalysis smoke tests passed")
    }
}

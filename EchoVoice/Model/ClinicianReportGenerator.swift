import Foundation
import UIKit

enum ClinicianReportGenerator {
    static func generateCSV(checkins: [CheckIn]) -> URL? {
        var csvText = String(localized: "Date,Speaking Rate (WPM),Pause Ratio (%),Pitch Stability,Articulation Rate (WPM excluding pauses),Status\n")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        for (index, c) in checkins.enumerated() {
            let dateStr = formatter.string(from: c.date)
            let wpmStr = String(format: "%.1f", c.wpm)
            let pauseStr = String(format: "%.1f", c.pauseRatio * 100)
            let pitchStr = String(format: "%.2f", c.pitch)
            let articStr = String(format: "%.2f", c.articulationRate)
            let status = c.flagged
                ? String(localized: "Mention to Clinician")
                : (index < SpeechTrend.minBaselineSamples ? String(localized: "Building Baseline") : String(localized: "No Change Flagged"))

            csvText += "\"\(dateStr)\",\(wpmStr),\(pauseStr),\(pitchStr),\(articStr),\"\(status)\"\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("EchoVoice_Speech_Journal_Report.csv")
        do {
            try csvText.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    static func generatePDF(checkins: [CheckIn], patientName: String = String(localized: "Loved one")) -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: String(localized: "EchoVoice AAC App"),
            kCGPDFContextAuthor: String(localized: "EchoVoice Patient Voice Journal"),
            kCGPDFContextTitle: String(localized: "EchoVoice Speech Journal Summary Report")
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth: CGFloat = 8.5 * 72.0
        let pageHeight: CGFloat = 11.0 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("EchoVoice_Clinician_Summary.pdf")

        do {
            try renderer.writePDF(to: pdfURL) { context in
                context.beginPage()

                let margin: CGFloat = 36.0
                var currentY: CGFloat = 40.0

                // Header Title
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                    .foregroundColor: UIColor(red: 0.118, green: 0.302, blue: 0.169, alpha: 1.0) // Forest #1E4D2B
                ]
                let title = String(localized: "EchoVoice Speech Journal — Summary Report")
                title.draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
                currentY += 32.0

                // Subtitle / Date
                let formatter = DateFormatter()
                formatter.dateStyle = .long

                let subAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
                let subtitle = String(localized: "Patient: %@  •  Report Date: %@  •  Total Check-ins: %@", defaultValue: "Patient: \(String(describing: patientName))  •  Report Date: \(String(describing: formatter.string(from: Date())))  •  Total Check-ins: \(String(describing: checkins.count))")
                subtitle.draw(at: CGPoint(x: margin, y: currentY), withAttributes: subAttributes)
                currentY += 24.0

                // Disclaimer box
                let disclaimerText = String(localized: "DISCLAIMER: EchoVoice is a personal voice journal, NOT a medical device. This report displays on-device acoustic measurements (speaking rate, pause duration, pitch stability) captured during repeat readings of one fixed reference sentence. Bring this summary to your Speech-Language Pathologist (SLP) to review trends.")
                let disclaimerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: 10),
                    .foregroundColor: UIColor.gray
                ]
                let disclaimerRect = CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: 40)
                disclaimerText.draw(in: disclaimerRect, withAttributes: disclaimerAttributes)
                currentY += 46.0

                // Divider line
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: currentY))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
                path.lineWidth = 1.0
                UIColor.lightGray.setStroke()
                path.stroke()
                currentY += 16.0

                // Table Header
                let headers = [String(localized: "Date"), String(localized: "Speaking Rate"), String(localized: "Pause Ratio"), String(localized: "Pitch Stability"), String(localized: "Status")]
                let colWidths: [CGFloat] = [130, 110, 90, 100, 110]

                var currentX = margin
                let headerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: UIColor(red: 0.118, green: 0.302, blue: 0.169, alpha: 1.0)
                ]

                for (idx, h) in headers.enumerated() {
                    h.draw(at: CGPoint(x: currentX, y: currentY), withAttributes: headerAttributes)
                    currentX += colWidths[idx]
                }
                currentY += 18.0

                // Table Rows
                let cellAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: UIColor.black
                ]

                let checkinDateFormatter = DateFormatter()
                checkinDateFormatter.dateStyle = .medium

                for (index, c) in checkins.enumerated().reversed().prefix(25) {
                    currentX = margin
                    let rowVals = [
                        checkinDateFormatter.string(from: c.date),
                        String(format: String(localized: "%.1f WPM"), c.wpm),
                        String(format: "%.1f %%", c.pauseRatio * 100),
                        String(format: "%.2f", c.pitch),
                        c.flagged
                            ? String(localized: "Worth Discussing")
                            : (index < SpeechTrend.minBaselineSamples ? String(localized: "Building Baseline") : String(localized: "No Change Flagged"))
                    ]

                    for (idx, val) in rowVals.enumerated() {
                        val.draw(at: CGPoint(x: currentX, y: currentY), withAttributes: cellAttributes)
                        currentX += colWidths[idx]
                    }
                    currentY += 16.0

                    if currentY > pageHeight - 50 {
                        context.beginPage()
                        currentY = 40.0
                    }
                }
            }
            return pdfURL
        } catch {
            return nil
        }
    }
}

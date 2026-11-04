import SwiftUI
import AppKit
import PaperReviewCore

struct AlignedTranscriptView: NSViewRepresentable {
    let transcript: Transcript
    let issues: [ReviewIssue]
    let uncertainLineIDs: [Int]
    let selectedIssueID: UUID?
    let onLineClick: (Int) -> Void
    func makeNSView(context: Context) -> TranscriptPageView { TranscriptPageView() }
    func updateNSView(_ view: TranscriptPageView, context: Context) {
        view.transcript = transcript; view.issues = issues; view.selectedIssueID = selectedIssueID
        view.uncertainLineIDs = uncertainLineIDs; view.onLineClick = onLineClick; view.needsDisplay = true
        view.setAccessibilityLabel("忠实转写。" + transcript.text)
        view.setAccessibilityRole(.textArea)
        view.setAccessibilityElement(true)
    }
}

final class TranscriptPageView: NSView {
    var transcript: Transcript?
    var issues: [ReviewIssue] = []
    var uncertainLineIDs: [Int] = []
    var selectedIssueID: UUID?
    var onLineClick: ((Int) -> Void)?
    var onIssueClick: ((UUID) -> Void)?
    var wordRegions: [WordRegion] = []
    var uncertainWordRects: [PageRect] = []
    var unlocatedTextRanges: [NSRange] = []
    var pageHeight: CGFloat = 0
    var zoom: CGFloat = 1
    var paperBackground = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private func lineText(_ line: DisplayLine, in transcript: Transcript) -> (text: String, leading: Int) {
        let raw = transcript.text(in: line)
        let leading = String(raw.prefix(while: { $0.isWhitespace }))
        return (String(raw.dropFirst(leading.count)).replacingOccurrences(of: "\n", with: " "), leading.utf16.count)
    }
    private func columnLeft(_ region: PageRect, in transcript: Transcript) -> Double {
        let positions = transcript.lines.filter {
            ($0.readingRegion ?? ReadingOrder.fullPage) == region && $0.hasGeometry && transcript.isAligned
        }.map(\.rect.x).sorted()
        let median = positions.isEmpty ? region.x + region.width * 0.04 : positions[(positions.count - 1) / 2]
        return min(region.x + region.width * 0.30, max(region.x + region.width * 0.03, median))
    }
    func requiredWidth() -> CGFloat {
        guard let transcript else { return 0 }
        let font = TextDrawing.font(zoom: zoom)
        return transcript.lines.map { line in
            let region = line.readingRegion ?? ReadingOrder.fullPage
            let text = lineText(line, in: transcript).text
            let measure = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            // Round outward: a sub-pixel shortage at the final glyph can make
            // TextKit wrap an otherwise exactly measured photographed row.
            return ceil((measure + 24 * zoom) / max(0.01, region.x + region.width - columnLeft(region, in: transcript)))
        }.max() ?? 0
    }
    func lineLayouts(width: CGFloat, pageHeight: CGFloat) -> [(DisplayLine, NSRect)] {
        guard let transcript else { return [] }
        let font = TextDrawing.font(zoom: zoom)
        var regions: [PageRect?] = []
        var bottoms: [CGFloat] = []
        return transcript.lines.map { line in
            let region = line.readingRegion
            let slot: Int
            if let index = regions.firstIndex(of: region) { slot = index }
            else { slot = regions.count; regions.append(region); bottoms.append(0) }
            let column = region ?? ReadingOrder.fullPage
            // One clean left edge per page. Handwritten row jitter is not indentation.
            let x = columnLeft(column, in: transcript) * width
            let available = max(1, (column.x + column.width) * width - x - 22 * zoom)
            let text = lineText(line, in: transcript).text
            let height = TextDrawing.height(text, width: available, font: font)
            let y = max(line.rect.y * pageHeight, bottoms[slot])
            let rect = NSRect(x: x, y: y, width: available, height: height)
            bottoms[slot] = rect.maxY + 8 * zoom
            return (line, rect)
        }
    }
    func requiredHeight(width: CGFloat, pageHeight: CGFloat) -> CGFloat {
        max(pageHeight, (lineLayouts(width: width, pageHeight: pageHeight).map { $0.1.maxY }.max() ?? 0) + 22 * zoom)
    }
    override func draw(_ dirtyRect: NSRect) {
        (paperBackground ? NSColor.white : WorkspaceStyle.pageColor).setFill(); bounds.fill()
        guard let transcript else { return }
        for (line, rect) in lineLayouts(width: bounds.width, pageHeight: pageHeight > 0 ? pageHeight : bounds.height) {
            let displayed = lineText(line, in: transcript)
            if issues.contains(where: { $0.id == selectedIssueID && $0.lineID == line.id }) {
                WorkspaceStyle.selectionColor.withAlphaComponent(0.5).setFill()
                rect.insetBy(dx: -5, dy: -4).fill()
            }
            let visible = NSRange(location: line.start + displayed.leading, length: max(0, line.length - displayed.leading))
            let highlights = issues.filter { $0.revision == transcript.revision && NSIntersectionRange($0.range, visible).length > 0 }.map { issue in
                let span = NSIntersectionRange(issue.range, visible)
                return (NSRange(location: span.location - line.start - displayed.leading, length: span.length),
                 issue.kind == .spelling ? NSColor.systemRed.withAlphaComponent(0.23) : NSColor.systemOrange.withAlphaComponent(0.25))
            }
            var uncertain = wordRegions.filter { $0.lineID == line.id && uncertainWordRects.contains($0.rect) }.compactMap { word -> NSRange? in
                guard let range = word.range else { return nil }
                return NSRange(location: range.location - line.start - displayed.leading, length: range.length)
            }
            uncertain += unlocatedTextRanges.compactMap { range in
                let overlap = NSIntersectionRange(range, line.range)
                return overlap.length > 0 ? NSRange(location: overlap.location - line.start - displayed.leading, length: overlap.length) : nil
            }
            TextDrawing.draw(displayed.text, in: rect,
                             font: TextDrawing.font(zoom: zoom), color: paperBackground ? .black : .textColor, highlights: highlights, uncertainties: uncertain)
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let layouts = lineLayouts(width: bounds.width, pageHeight: pageHeight > 0 ? pageHeight : bounds.height)
        if let transcript {
            for (line, rect) in layouts where rect.contains(point) {
                let displayed = lineText(line, in: transcript)
                if let index = TextDrawing.characterIndex(point, text: displayed.text, rect: rect, font: TextDrawing.font(zoom: zoom)),
                   let issue = issues.first(where: { $0.revision == transcript.revision && NSLocationInRange(line.start + displayed.leading + index, $0.range) }) {
                    onIssueClick?(issue.id); return
                }
            }
        }
        if let nearest = layouts.min(by: { abs($0.1.midY - point.y) < abs($1.1.midY - point.y) }) {
            onLineClick?(nearest.0.id)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "复制忠实原文", action: #selector(copyTranscript), keyEquivalent: "c")
        item.target = self; menu.addItem(item)
        return menu
    }
    @objc private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript?.text ?? "", forType: .string)
    }
}

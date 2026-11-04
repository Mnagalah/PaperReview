import Foundation

/// English book spreads are read page by page, not by the height of a line in the photograph.
public enum ReadingOrder {
    public static let fullPage = PageRect(x: 0, y: 0, width: 1, height: 1)

    /// Require a persistent central gutter with several substantial rows on BOTH
    /// sides. A short line, an indentation, or slanted fragments alone is not a page break.
    public static func regions(hints: [TextHint], aspectRatio: Double) -> [PageRect] {
        let full = [fullPage]
        guard aspectRatio >= 1.15 else { return full }
        let valid = hints.filter { $0.rect.width > 0 && $0.rect.height > 0 && !$0.text.isEmpty }
        var spans: [(start: Double, end: Double)] = []
        for hint in valid.sorted(by: { $0.rect.x < $1.rect.x }) {
            let start = max(0, hint.rect.x), end = min(1, hint.rect.x + hint.rect.width)
            if let last = spans.last, start <= last.end {
                spans[spans.count - 1].end = max(last.end, end)
            } else { spans.append((start, end)) }
        }
        var gaps: [(cut: Double, width: Double)] = []
        for (left, right) in zip(spans, spans.dropFirst()) {
            let gap = right.start - left.end, cut = (left.end + right.start) / 2
            guard gap >= 0.025, (0.28...0.72).contains(cut) else { continue }
            func substantial(_ side: [TextHint]) -> Bool {
                let rows = TextRowGrouping.groups(side)
                let letters = side.reduce(0) { $0 + $1.text.filter(\.isLetter).count }
                let minX = side.map(\.rect.x).min() ?? 0
                let maxX = side.map { $0.rect.x + $0.rect.width }.max() ?? 0
                let minY = side.map(\.rect.y).min() ?? 0
                let maxY = side.map { $0.rect.y + $0.rect.height }.max() ?? 0
                return rows.count >= 3 && letters >= 30 && maxX - minX >= 0.16 && maxY - minY >= 0.10
            }
            guard substantial(valid.filter { $0.rect.x + $0.rect.width <= cut }),
                  substantial(valid.filter { $0.rect.x >= cut }) else { continue }
            gaps.append((cut, gap))
        }
        guard let gap = gaps.max(by: { $0.width < $1.width }) else { return full }
        return [PageRect(x: 0, y: 0, width: gap.cut, height: 1),
                PageRect(x: gap.cut, y: 0, width: 1 - gap.cut, height: 1)]
    }

    public static func contains(_ region: PageRect, hint: TextHint) -> Bool {
        let center = hint.rect.x + hint.rect.width / 2
        return center >= region.x && center < region.x + region.width
    }

    /// Regions are in reading order. Never merge a left-page fragment with a right-page fragment.
    public static func rowGroups(hints: [TextHint], regions: [PageRect]) -> [[Int]] {
        regions.flatMap { region in
            let indices = hints.indices.filter { contains(region, hint: hints[$0]) }
            return TextRowGrouping.groups(indices.map { hints[$0] }).map { group in group.map { indices[$0] } }
        }
    }

    /// Accepts a prefix of page responses so the first page can be shown immediately.
    /// Each response is aligned independently; a failed alignment on one page
    /// must not destroy the usable geometry of the other page.
    public static func transcript(texts: [String], hints: [TextHint], regions: [PageRect]) -> Transcript {
        precondition(texts.count <= regions.count)
        if regions.count == 1 { return LineAlignment.makeTranscript(text: texts.first ?? "", hints: hints) }
        var text = "", lines: [DisplayLine] = []
        var aligned = false
        for (index, pageText) in texts.enumerated() {
            let region = regions[index]
            let indices = hints.indices.filter { contains(region, hint: hints[$0]) }
            let part = LineAlignment.makeTranscript(text: pageText, hints: indices.map { hints[$0] })
            if !lines.isEmpty {
                // The separator belongs to the previous line's range, preserving
                // complete UTF-16 coverage without adding a fake photographed row.
                let last = lines.removeLast()
                lines.append(DisplayLine(id: last.id, start: last.start, length: last.length + 1, rect: last.rect,
                    sourceRowID: last.sourceRowID, geometryAvailable: last.geometryAvailable, readingRegion: last.readingRegion))
                text += "\n"
            }
            let offset = text.utf16.count
            for line in part.lines {
                let hasGeometry = part.isAligned && line.hasGeometry
                // A weak physical row can retain its approximate display slot
                // without being eligible for photo/word anchoring. Its row ID
                // means the slot is already in full-photo coordinates.
                let pageCoordinates = part.isAligned && (line.hasGeometry || line.sourceRowID != nil)
                let rect = pageCoordinates ? line.rect : PageRect(x: region.x + line.rect.x * region.width,
                    y: region.y + line.rect.y * region.height, width: line.rect.width * region.width,
                    height: line.rect.height * region.height)
                let sourceID = line.sourceRowID.flatMap { row in indices.indices.contains(row - 1) ? indices[row - 1] + 1 : nil }
                lines.append(DisplayLine(id: lines.count + 1, start: line.start + offset, length: line.length,
                    rect: rect, sourceRowID: sourceID, geometryAvailable: hasGeometry, readingRegion: region))
            }
            text += pageText
            aligned = aligned || part.isAligned
        }
        return Transcript(text: text, lines: lines, isAligned: aligned)
    }

    /// Word substitutions keep their page and line ownership; running a new global
    /// text alignment here could move repeated phrases across a page boundary.
    public static func replacing(_ replacements: [(NSRange, String)], in transcript: Transcript) -> Transcript {
        let text = NSMutableString(string: transcript.text)
        for (range, value) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            precondition(transcript.lines.contains { $0.start <= range.location && NSMaxRange(range) <= NSMaxRange($0.range) })
            text.replaceCharacters(in: range, with: value)
        }
        func delta(_ edit: (NSRange, String)) -> Int { edit.1.utf16.count - edit.0.length }
        let lines = transcript.lines.map { line in
            let before = replacements.filter { NSMaxRange($0.0) <= line.start }.reduce(0) { $0 + delta($1) }
            let inside = replacements.filter { $0.0.location >= line.start && NSMaxRange($0.0) <= NSMaxRange(line.range) }
                .reduce(0) { $0 + delta($1) }
            return DisplayLine(id: line.id, start: line.start + before, length: line.length + inside, rect: line.rect,
                sourceRowID: line.sourceRowID, geometryAvailable: line.geometryAvailable, readingRegion: line.readingRegion)
        }
        return Transcript(text: text as String, lines: lines, isAligned: transcript.isAligned)
    }

    public static func pageTranscripts(_ transcript: Transcript) -> [(region: PageRect, transcript: Transcript)] {
        var regions: [PageRect] = []
        for line in transcript.lines {
            let region = line.readingRegion ?? fullPage
            if !regions.contains(region) { regions.append(region) }
        }
        return regions.map { region in
            let lines = transcript.lines.filter { ($0.readingRegion ?? fullPage) == region }
            let text = lines.map { transcript.text(in: $0) }.joined()
            return (region, LineAlignment.fallback(text))
        }
    }
}

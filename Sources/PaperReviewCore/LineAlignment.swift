import Foundation

/// Vision supplies geometry hints only. All displayed characters come from the MiniCPM transcript.
public enum LineAlignment {
    private struct Glyph {
        let value: Character
        let offset: Int
    }
    private static func glyphs(_ text: String) -> [Glyph] {
        var result: [Glyph] = []
        var offset = 0
        for character in text {
            for lower in String(character).lowercased() where lower.isLetter || lower.isNumber {
                result.append(Glyph(value: lower, offset: offset))
            }
            offset += String(character).utf16.count
        }
        return result
    }

    public static func makeTranscript(text: String, hints: [TextHint]) -> Transcript {
        let source = glyphs(text)
        let hints = hints.filter { !$0.text.isEmpty && $0.rect.height > 0 && $0.rect.width > 0 }
        let hintGlyphs = hints.map { glyphs($0.text) }
        let target = hintGlyphs.flatMap { $0.map(\.value) }
        // Keep the quadratic alignment bounded for classroom-size essays.
        guard source.count > 0, target.count > 0, source.count <= 8192, target.count <= 8192, source.count * target.count <= 8_000_000 else {
            return fallback(text)
        }
        let rows = source.count + 1, columns = target.count + 1
        var costs = [UInt16](repeating: 0, count: rows * columns)
        for i in 0..<rows { costs[i * columns] = UInt16(i) }
        for j in 0..<columns { costs[j] = UInt16(j) }
        for i in 1..<rows {
            for j in 1..<columns {
                let penalty: UInt16 = source[i - 1].value == target[j - 1] ? 0 : 1
                costs[i * columns + j] = min(costs[(i - 1) * columns + j] + 1,
                    costs[i * columns + j - 1] + 1, costs[(i - 1) * columns + j - 1] + penalty)
            }
        }
        var mapping = [Int: Int]()
        var i = source.count, j = target.count
        while i > 0 && j > 0 {
            let equal = source[i - 1].value == target[j - 1]
            if costs[i * columns + j] == costs[(i - 1) * columns + j - 1] + (equal ? 0 : 1) {
                if equal { mapping[j - 1] = source[i - 1].offset }
                i -= 1; j -= 1
            } else if costs[i * columns + j] == costs[(i - 1) * columns + j] + 1 {
                i -= 1
            } else { j -= 1 }
        }
        if let partial = physicalRows(text: text, hints: hints, hintGlyphs: hintGlyphs, mapping: mapping) { return partial }
        guard Double(mapping.count) / Double(max(source.count, target.count)) >= 0.60 else { return fallback(text) }
        var cursor = 0
        var starts: [Int] = []
        for glyphs in hintGlyphs {
            let matched = (cursor..<(cursor + glyphs.count)).compactMap { mapping[$0] }
            guard !glyphs.isEmpty, Double(matched.count) / Double(glyphs.count) >= 0.45,
                  let first = matched.first else { return fallback(text) }
            starts.append(first)
            cursor += glyphs.count
        }
        let ns = text as NSString
        // A split is allowed only at original whitespace; no character is substituted or dropped.
        // Keep an undetected heading/prompt separate. Do not pretend that its
        // characters share the first detected handwriting row's coordinates.
        let leadingBreak = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: starts[0]))
        let prefixEnd = leadingBreak.location == NSNotFound ? 0 : NSMaxRange(leadingBreak)
        let hasPrefix = prefixEnd > 0 && !ns.substring(to: prefixEnd).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var boundaries = [hasPrefix ? prefixEnd : 0]
        for start in starts.dropFirst() {
            var boundary = start
            while boundary > boundaries.last! && boundary > 0 {
                let char = ns.substring(with: NSRange(location: boundary - 1, length: 1))
                if char.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { break }
                boundary -= 1
            }
            guard boundary > boundaries.last! else { return fallback(text) }
            boundaries.append(boundary)
        }
        boundaries.append(ns.length)
        var lines: [DisplayLine] = []
        if hasPrefix {
            lines.append(DisplayLine(id: 1, start: 0, length: prefixEnd,
                rect: PageRect(x: 0.05, y: 0.015, width: 0.9, height: 0.035), geometryAvailable: false))
        }
        lines += hints.indices.map { index in
            DisplayLine(id: index + 1 + (hasPrefix ? 1 : 0), start: boundaries[index], length: boundaries[index + 1] - boundaries[index],
                        rect: hints[index].rect, sourceRowID: index + 1)
        }
        return Transcript(text: text, lines: lines, isAligned: true)
    }

    /// Preserve usable rows when a difficult row drags down the whole-page
    /// match. Row count alone is never enough: a strict majority (at least two)
    /// must have independently matched letters inside the SAME source row.
    private static func physicalRows(text: String, hints: [TextHint], hintGlyphs: [[Glyph]],
                                     mapping: [Int: Int]) -> Transcript? {
        var starts: [Int] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byLines) { value, _, enclosing, _ in
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                starts.append(NSRange(enclosing, in: text).location)
            }
        }
        guard starts.count == hints.count, starts.count >= 3 else { return nil }
        starts[0] = 0
        let ends = Array(starts.dropFirst()) + [text.utf16.count]
        let ranges = zip(starts, ends).map { NSRange(location: $0, length: $1 - $0) }
        var cursor = 0
        let reliable = hintGlyphs.indices.map { index -> Bool in
            let glyphs = hintGlyphs[index]
            let matched = (cursor..<(cursor + glyphs.count)).compactMap { mapping[$0] }
            cursor += glyphs.count
            let inside = matched.filter { NSLocationInRange($0, ranges[index]) }
            return matched.count >= 4 && Double(matched.count) / Double(max(1, glyphs.count)) >= 0.45
                && Double(inside.count) / Double(matched.count) >= 0.80
        }
        let count = reliable.filter { $0 }.count
        guard count >= 2, count * 2 > hints.count, count < hints.count else { return nil }
        let lines = hints.indices.map { index in
            DisplayLine(id: index + 1, start: ranges[index].location, length: ranges[index].length,
                rect: hints[index].rect, sourceRowID: index + 1, geometryAvailable: reliable[index])
        }
        return Transcript(text: text, lines: lines, isAligned: true)
    }

    /// Independent text hints can flag a disagreement, but can never replace the primary OCR text.
    public static func uncertainLines(_ transcript: Transcript, hints: [TextHint]) -> [Int] {
        guard transcript.isAligned, transcript.lines.count == hints.count else { return [] }
        func normalized(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        return zip(transcript.lines, hints).compactMap { line, hint in
            guard hint.confidence >= 0.9 else { return nil }
            return normalized(transcript.text(in: line)) == normalized(hint.text) ? nil : line.id
        }
    }

    public static func fallback(_ text: String) -> Transcript {
        var ranges: [NSRange] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            var end = text.index(cursor, offsetBy: 76, limitedBy: lineEnd) ?? lineEnd
            if end < lineEnd {
                if let space = text[cursor..<end].lastIndex(where: { $0.isWhitespace }), space > cursor {
                    end = text.index(after: space)
                }
            } else if lineEnd < text.endIndex { end = text.index(after: lineEnd) }
            if end == cursor { end = text.index(after: cursor) }
            ranges.append(NSRange(cursor..<end, in: text))
            cursor = end
        }
        let step = min(0.048, 0.84 / Double(max(1, ranges.count)))
        let ns = text as NSString
        let lines = ranges.enumerated().map { index, range in
            let length = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).count
            return DisplayLine(id: index + 1, start: range.location, length: range.length,
                rect: PageRect(x: 0.07, y: 0.06 + Double(index) * step,
                               width: min(0.86, max(0.12, Double(length) / 76 * 0.86)), height: step * 0.67))
        }
        return Transcript(text: text, lines: lines, isAligned: false)
    }
}

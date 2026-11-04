import Foundation

public struct PageAnnotation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case lineNumber, formLabel }
    public let kind: Kind
    public let rect: PageRect
    public let text: String?
    public init(kind: Kind, rect: PageRect, text: String? = nil) { self.kind = kind; self.rect = rect; self.text = text }
}

/// Separates demonstrated workbook furniture from student language. An ordinary
/// number in the essay is never discarded merely because it is a number.
public enum PageScaffolding {
    public static let version = "workbook-margin-v2"
    private static func heading(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "’", with: "'") == "student's writing"
    }
    public static func covers(_ rect: PageRect, with annotation: PageAnnotation) -> Bool {
        let x = rect.x + rect.width / 2, y = rect.y + rect.height / 2
        return x >= annotation.rect.x && x <= annotation.rect.x + annotation.rect.width
            && y >= annotation.rect.y && y <= annotation.rect.y + annotation.rect.height
    }
    public static func annotations(fragments: [TextHint], rectangles: [PageRect], aspectRatio: Double) -> [PageAnnotation] {
        let hasHeading = fragments.contains { heading($0.text) }
        let candidates = rectangles.filter { rect in
            let ratio = rect.width * aspectRatio / max(0.001, rect.height)
            return (rect.x < 0.22 || rect.x > 0.78) && (0.025...0.085).contains(rect.width)
                && (0.03...0.14).contains(rect.height) && (0.5...1.8).contains(ratio)
        }.filter { rect in
            !rectangles.contains { other in
                other.width * other.height > rect.width * rect.height * 1.4
                    && other.width < 0.10 && other.height < 0.16
                    && other.x <= rect.x && other.y <= rect.y
                    && other.x + other.width >= rect.x + rect.width && other.y + other.height >= rect.y + rect.height
            }
        }
        var columns: [[PageRect]] = []
        for rect in candidates.sorted(by: { $0.x < $1.x }) {
            if let slot = columns.firstIndex(where: { column in
                let center = column.map { $0.x + $0.width / 2 }.reduce(0, +) / Double(column.count)
                return abs(center - (rect.x + rect.width / 2)) < 0.028
            }) {
                columns[slot].append(rect)
            } else { columns.append([rect]) }
        }
        var result: [PageAnnotation] = []
        // A demonstrated worksheet header is not part of the essay. Limit this
        // to the same physical page, so a right-page continuation above the
        // left-page heading is never mistaken for instructions.
        let pageRegions = ReadingOrder.regions(hints: fragments, aspectRatio: aspectRatio)
        for label in fragments where heading(label.text) {
            guard let region = pageRegions.first(where: { ReadingOrder.contains($0, hint: label) }) else { continue }
            let above = fragments.filter { ReadingOrder.contains(region, hint: $0) && $0.rect.y + $0.rect.height <= label.rect.y }
            let hasChecklist = above.contains { $0.text.lowercased().contains("reflection checklist") }
            if hasChecklist {
                result += above.map { .init(kind: .formLabel, rect: $0.rect, text: $0.text) }
                result.append(.init(kind: .formLabel, rect: label.rect, text: label.text))
            }
        }
        for column in columns where column.count >= 3 {
            let boxes = column.sorted { $0.y < $1.y }
            let distances = zip(boxes, boxes.dropFirst()).map { $1.y - $0.y }
            guard let minimum = distances.min(), let maximum = distances.max(), minimum > 0.025, maximum < minimum * 2.2 else { continue }
            let values = boxes.compactMap { box in
                fragments.first { covers($0.rect, with: .init(kind: .lineNumber, rect: box)) }
                    .flatMap { Int($0.text.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) }
            }
            let numericSequence = values.count >= 3 && zip(values, values.dropFirst()).allSatisfy { $1 == $0 + 1 }
            guard hasHeading || numericSequence else { continue }
            let nearby = boxes.filter { box in
                fragments.contains { hint in
                    let overlap = min(box.y + box.height, hint.rect.y + hint.rect.height) - max(box.y, hint.rect.y)
                    let gap = max(hint.rect.x - box.x - box.width, box.x - hint.rect.x - hint.rect.width)
                    return hint.text.filter(\.isLetter).count >= 8 && hint.rect.width > 0.15
                        && overlap > min(box.height, hint.rect.height) * 0.4 && gap >= 0 && gap < 0.12
                }
            }
            guard nearby.count >= 2 else { continue }
            result += boxes.map { box in
                let text = fragments.first { covers($0.rect, with: .init(kind: .lineNumber, rect: box)) }?.text
                return .init(kind: .lineNumber, rect: box, text: text)
            }
            // Short labels in the same proven margin column are form furniture too.
            for hint in fragments where hint.rect.width < 0.15 {
                let center = hint.rect.x + hint.rect.width / 2
                let columnCenter = boxes[0].x + boxes[0].width / 2
                if abs(center - columnCenter) < 0.035 && hint.rect.y >= boxes[0].y - 0.03
                    && hint.rect.y <= boxes.last!.y + boxes.last!.height + 0.10
                    && !result.contains(where: { covers(hint.rect, with: $0) }) {
                    result.append(.init(kind: .formLabel, rect: hint.rect, text: hint.text))
                }
            }
        }
        if !result.isEmpty {
            result += fragments.filter { hint in heading(hint.text) && !result.contains(where: { covers(hint.rect, with: $0) }) }
                .map { .init(kind: .formLabel, rect: $0.rect, text: $0.text) }
        }
        return result
    }

    /// Recover old unmasked OCR only when a repeated boxed margin has independently
    /// been found AND the raw output contains a consecutive row-prefix sequence.
    /// Digits in prose, years, and punctuated student lists are not matched.
    public static func bodyText(_ raw: String, annotations: [PageAnnotation]) -> String {
        guard annotations.filter({ $0.kind == .lineNumber && $0.rect.x < 0.22 }).count >= 3 else { return raw }
        var cleaned = raw
        if annotations.contains(where: { $0.kind == .formLabel && $0.text.map(heading) == true }) {
            // Older alignment could attach the template heading to the first
            // handwriting row instead of keeping its original newline.
            let label = try! NSRegularExpression(pattern: "(?i)^Student['’]s Writing(?:[ \\t]+|\\n|$)")
            if let match = label.firstMatch(in: cleaned, range: NSRange(location: 0, length: cleaned.utf16.count)) {
                cleaned = (cleaned as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        let lines = cleaned.components(separatedBy: "\n")
        let regex = try! NSRegularExpression(pattern: "^([ \\t]*)([0-9]{1,3})([ \\t]+|(?=[A-Za-z]|$))")
        let numbered = lines.enumerated().compactMap { index, line -> (Int, NSRange, Int)? in
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let value = Int(ns.substring(with: match.range(at: 2))) else { return nil }
            return (index, NSRange(location: match.range(at: 2).location,
                length: NSMaxRange(match.range) - match.range(at: 2).location), value)
        }
        guard numbered.count >= 3, zip(numbered, numbered.dropFirst()).allSatisfy({ $1.2 == $0.2 + 1 }) else { return cleaned }
        let ranges = Dictionary(uniqueKeysWithValues: numbered.map { ($0.0, $0.1) })
        return lines.enumerated().compactMap { index, line -> String? in
            if heading(line) { return nil }
            guard let range = ranges[index] else { return line }
            return (line as NSString).replacingCharacters(in: range, with: "")
        }.joined(separator: "\n")
    }
}

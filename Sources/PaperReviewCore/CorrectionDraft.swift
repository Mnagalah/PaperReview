import Foundation

/// A minimal edit of a model's internal proofreading draft. Positions and
/// quotations always come from the unchanged OCR transcript, never the model.
public struct CorrectionDraft: Codable, Sendable, Identifiable {
    public let id: Int
    public let lineID: Int
    public let start: Int
    public let length: Int
    public let quote: String
    public let suggestion: String
    public var range: NSRange { NSRange(location: start, length: length) }
}

enum CorrectionDiff {
    static func merge(_ batches: [[CorrectionDraft]]) throws -> [CorrectionDraft] {
        var drafts: [CorrectionDraft] = []
        for draft in batches.flatMap({ $0 }) where !drafts.contains(where: { $0.range == draft.range && $0.suggestion == draft.suggestion }) {
            drafts.append(draft)
        }
        guard drafts.count <= 100 else { throw ModelError.invalidResponse("审核候选数量异常") }
        return drafts.sorted { $0.start == $1.start ? $0.suggestion < $1.suggestion : $0.start < $1.start }.enumerated().map { index, item in
            CorrectionDraft(id: index + 1, lineID: item.lineID, start: item.start, length: item.length, quote: item.quote, suggestion: item.suggestion)
        }
    }
    private struct Token {
        let text: String
        let range: NSRange
    }
    private struct Span { var a: Range<Int>; var b: Range<Int> }
    private static func tokens(_ text: String) -> [Token] {
        let pattern = #"\w+(?:['’]\w+)*|[^\w\s]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { Token(text: ns.substring(with: $0.range), range: $0.range) }
    }

    static func edits(source: Transcript, corrected: String) throws -> [CorrectionDraft] {
        let original = source.text as NSString, replacement = corrected as NSString
        let a = tokens(source.text), b = tokens(corrected)
        let difference = b.map(\.text).difference(from: a.map(\.text))
        var removed: Set<Int> = [], inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var spans: [Span] = [], i = 0, j = 0
        while i < a.count || j < b.count {
            if removed.contains(i) || inserted.contains(j) {
                let old = i, new = j
                while removed.contains(i) { i += 1 }
                while inserted.contains(j) { j += 1 }
                if i - old == j - new && i > old {
                    // Adjacent spelling, tense and case changes remain separate
                    // words, rather than one oversized quotation.
                    for offset in 0..<(i - old) {
                        spans.append(Span(a: (old + offset)..<(old + offset + 1), b: (new + offset)..<(new + offset + 1)))
                    }
                } else { spans.append(Span(a: old..<i, b: new..<j)) }
            } else { i += 1; j += 1 }
        }
        // Nonempty source anchors also represent inserted words/punctuation.
        for index in spans.indices where spans[index].a.isEmpty {
            let old = spans[index].a.lowerBound, new = spans[index].b.lowerBound
            if old > 0 && new > 0 && NSMaxRange(b[new - 1].range) == b[new].range.location {
                spans[index].a = (old - 1)..<old
                spans[index].b = (new - 1)..<spans[index].b.upperBound
            } else if old < a.count {
                spans[index].a = old..<(old + 1)
                spans[index].b = new..<(spans[index].b.upperBound + 1)
            } else if old > 0 {
                spans[index].a = (old - 1)..<old
                spans[index].b = (new - 1)..<spans[index].b.upperBound
            } else { throw ModelError.invalidResponse("审核候选扩写了空原文") }
        }
        var merged: [Span] = []
        for span in spans {
            if let last = merged.last, span.a.lowerBound < last.a.upperBound {
                merged[merged.count - 1] = Span(a: last.a.lowerBound..<max(last.a.upperBound, span.a.upperBound),
                    b: last.b.lowerBound..<max(last.b.upperBound, span.b.upperBound))
            } else { merged.append(span) }
        }
        return try merged.enumerated().map { index, span in
            let start = a[span.a.lowerBound].range.location
            let length = NSMaxRange(a[span.a.upperBound - 1].range) - start
            let range = NSRange(location: start, length: length)
            let quote = original.substring(with: range)
            let suggestion = span.b.isEmpty ? "" : replacement.substring(with: NSRange(location: b[span.b.lowerBound].range.location,
                length: NSMaxRange(b[span.b.upperBound - 1].range) - b[span.b.lowerBound].range.location))
            guard let line = source.lines.first(where: { NSLocationInRange(start, $0.range) }) else {
                throw ModelError.invalidResponse("审核候选不在当前原文范围内")
            }
            return CorrectionDraft(id: index + 1, lineID: line.id, start: start, length: length, quote: quote, suggestion: suggestion)
        }
    }
}

public struct ReviewDraftDecision: Codable, Sendable {
    public let id: Int
    public let accept: Bool
    public let kind: IssueKind
    public let explanation: String
    public let basis: String?
    public init(id: Int, accept: Bool, kind: IssueKind, explanation: String, basis: String? = nil) {
        self.id = id; self.accept = accept; self.kind = kind; self.explanation = explanation; self.basis = basis
    }
}

public struct ReviewModelEvidence: Codable, Sendable {
    public let version: String
    public let stageSeconds: [String: Double]
    public let drafts: [CorrectionDraft]
    public let decisions: [ReviewDraftDecision]
}

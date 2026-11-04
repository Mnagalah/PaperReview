import Foundation

/// A physical word (or a small joined/split word group), not a corrected reading.
public struct WordRegion: Codable, Sendable {
    public let id: Int
    public let lineID: Int
    public let rect: PageRect
    public let hint: String
    public let original: String?
    public let start: Int?
    public let length: Int?
    public let sourceWordCount: Int
    public var range: NSRange? {
        guard let start, let length else { return nil }
        return NSRange(location: start, length: length)
    }
    public var cropHint: WordHint { WordHint(lineID: lineID, text: hint, rect: rect, confidence: 0) }
}

public struct WordInventory: Sendable {
    public let regions: [WordRegion]
    public let transcriptWords: Int
    public let locatedWords: Int
    public let unlocatedRanges: [NSRange]
}

/// Aligns whole-page tokens to physical word boxes, allowing joined words such as
/// "havea" versus "have a". A count mismatch must not skip the rest of the line.
public enum WordAlignment {
    private struct Token { let text: String; let range: NSRange }
    private struct Step { let source: Int; let target: Int }
    private static let pattern = "[A-Za-z]+(?:['’][A-Za-z]+)*|[0-9]+"
    private static func tokens(_ text: String) -> [Token] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { Token(text: ns.substring(with: $0.range), range: $0.range) }
    }
    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs.lowercased()), b = Array(rhs.lowercased())
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var row = [i + 1] + [Int](repeating: 0, count: b.count)
            for j in b.indices {
                row[j + 1] = min(previous[j + 1] + 1, row[j] + 1, previous[j] + (character == b[j] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }
    private static func union(_ words: ArraySlice<WordHint>) -> PageRect {
        let x = words.map(\.rect.x).min()!, y = words.map(\.rect.y).min()!
        return PageRect(x: x, y: y, width: words.map { $0.rect.x + $0.rect.width }.max()! - x,
                        height: words.map { $0.rect.y + $0.rect.height }.max()! - y)
    }

    public static func inventory(_ transcript: Transcript, hints: [WordHint]) -> WordInventory {
        var regions: [WordRegion] = [], unlocated: [NSRange] = []
        var wordCount = 0, located = 0
        for line in transcript.lines {
            let ns = transcript.text(in: line) as NSString
            let source = tokens(ns as String)
            wordCount += source.count
            let target = transcript.isAligned && line.hasGeometry
                ? hints.filter { $0.lineID == (line.sourceRowID ?? line.id) }.sorted { $0.rect.x < $1.rect.x } : []
            let rows = source.count + 1, columns = target.count + 1
            var cost = [Double](repeating: .infinity, count: rows * columns)
            var steps = [Step?](repeating: nil, count: cost.count)
            cost[0] = 0
            for i in 0..<rows {
                for j in 0..<columns where cost[i * columns + j].isFinite {
                    func propose(_ a: Int, _ b: Int, _ penalty: Double) {
                        let index = (i + a) * columns + j + b
                        let candidate = cost[i * columns + j] + penalty
                        if candidate < cost[index] { cost[index] = candidate; steps[index] = Step(source: a, target: b) }
                    }
                    if i < source.count { propose(1, 0, 1.1) }
                    if j < target.count { propose(0, 1, 1.1) }
                    guard i < source.count, j < target.count else { continue }
                    for a in 1...min(3, source.count - i) {
                        let range = NSRange(location: source[i].range.location,
                            length: NSMaxRange(source[i + a - 1].range) - source[i].range.location)
                        let original = ns.substring(with: range)
                        // A multiword replacement cannot swallow punctuation between words.
                        if a > 1 && original.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && $0 != "'" && $0 != "’" }) { continue }
                        let left = source[i..<(i + a)].map(\.text).joined()
                        for b in 1...min(3, target.count - j) {
                            if a > 1 && b > 1 { continue }
                            let right = target[j..<(j + b)].map(\.text).joined()
                            // Joining/splitting letters is not evidence that an
                            // entire source word vanished from a tight crop.
                            // "my homework" must not become the box for "homework".
                            if a > 1 && source[i..<(i + a)].contains(where: { $0.text.lowercased() == right.lowercased() }) { continue }
                            if b > 1 && target[j..<(j + b)].contains(where: { $0.text.lowercased() == left.lowercased() }) { continue }
                            let difference = Double(distance(left, right)) / Double(max(left.count, right.count, 1))
                            if a == 1 && b == 1 && difference > 0.65 { continue }
                            if a + b > 2 && difference > 0.20 { continue }
                            let penalty = difference * Double(max(a, b)) + Double(a + b - 2) * 0.15
                            propose(a, b, penalty)
                        }
                    }
                }
            }
            var pairs: [(Range<Int>, Range<Int>)] = []
            var i = source.count, j = target.count
            while i > 0 || j > 0 {
                guard let step = steps[i * columns + j] else { break }
                pairs.append(((i - step.source)..<i, (j - step.target)..<j))
                i -= step.source; j -= step.target
            }
            for (a, b) in pairs.reversed() {
                let range = a.isEmpty ? nil : NSRange(location: line.start + source[a.lowerBound].range.location,
                    length: NSMaxRange(source[a.upperBound - 1].range) - source[a.lowerBound].range.location)
                guard !b.isEmpty else { if let range { unlocated.append(range) }; continue }
                let words = target[b]
                let original = range.map { (transcript.text as NSString).substring(with: $0) }
                located += a.count
                regions.append(WordRegion(id: regions.count + 1, lineID: line.id, rect: union(words),
                    hint: words.map(\.text).joined(separator: " "), original: original,
                    start: range?.location, length: range?.length, sourceWordCount: b.count))
            }
        }
        // Even if whole-page alignment fails, every detected physical word is read
        // independently. Unanchored readings are retained as evidence, not inserted.
        let representedLines = Set(transcript.lines.filter { line in regions.contains { $0.lineID == line.id } }.map { $0.sourceRowID ?? $0.id })
        for hint in hints where !transcript.isAligned || !representedLines.contains(hint.lineID) {
            regions.append(WordRegion(id: regions.count + 1, lineID: hint.lineID, rect: hint.rect,
                hint: hint.text, original: nil, start: nil, length: nil, sourceWordCount: 1))
        }
        return WordInventory(regions: regions, transcriptWords: wordCount, locatedWords: located, unlocatedRanges: unlocated)
    }

    /// Word crops do not own surrounding punctuation. Strip boundary punctuation,
    /// reject explanations/line breaks, and keep internal apostrophes and spaces.
    public static func lexicalReading(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"“”()[]{}"))
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80,
              !trimmed.contains(where: { $0.isNewline }),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " " || $0 == "'" || $0 == "-") || $0 == "’" }) else { return nil }
        return trimmed
    }
}

public struct WordCheck: Codable, Sendable {
    public let region: WordRegion
    public let isolated: String?
    public let sourceReading: String?
    public let sourceChecked: Bool?
    public var scores: [String: Double]
    public var selected: String?
    public var evidence: String?
    public var unresolved: Bool
    public init(region: WordRegion, isolated: String?, sourceReading: String? = nil, sourceChecked: Bool? = nil) {
        self.region = region; self.isolated = isolated; scores = [:]; selected = nil; evidence = nil; unresolved = false
        self.sourceReading = sourceReading; self.sourceChecked = sourceChecked
    }
    public var readingsDisagree: Bool {
        isolated == nil || isolated != selected || (sourceChecked == true && (sourceReading == nil || sourceReading != selected))
    }
}

public struct WordVerificationSummary: Codable, Sendable {
    public let totalRegions: Int
    public let checkedRegions: Int
    public let transcriptWords: Int
    public let locatedWords: Int
    public let unresolvedRegions: Int
    public init(totalRegions: Int, checkedRegions: Int, transcriptWords: Int, locatedWords: Int, unresolvedRegions: Int) {
        self.totalRegions = totalRegions; self.checkedRegions = checkedRegions
        self.transcriptWords = transcriptWords; self.locatedWords = locatedWords; self.unresolvedRegions = unresolvedRegions
    }
}

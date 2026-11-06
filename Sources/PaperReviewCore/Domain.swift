import Foundation

public struct PageRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct TextHint: Codable, Sendable {
    public let text: String
    public let rect: PageRect
    public let confidence: Double
    public init(text: String, rect: PageRect, confidence: Double = 1) { self.text = text; self.rect = rect; self.confidence = confidence }
}

public struct DisplayLine: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let start: Int
    public let length: Int
    public let rect: PageRect
    public let sourceRowID: Int?
    public let geometryAvailable: Bool?
    public let readingRegion: PageRect?
    public var hasGeometry: Bool { geometryAvailable != false }
    public var range: NSRange { NSRange(location: start, length: length) }
    public init(id: Int, start: Int, length: Int, rect: PageRect, sourceRowID: Int? = nil, geometryAvailable: Bool? = nil,
                readingRegion: PageRect? = nil) {
        self.id = id; self.start = start; self.length = length; self.rect = rect
        self.sourceRowID = sourceRowID; self.geometryAvailable = geometryAvailable
        self.readingRegion = readingRegion
    }
}

public struct Transcript: Codable, Equatable, Sendable {
    public let text: String
    public let revision: UUID
    public let lines: [DisplayLine]
    public let isAligned: Bool
    public var isFullyAligned: Bool { isAligned && lines.allSatisfy(\.hasGeometry) }
    public init(text: String, revision: UUID = UUID(), lines: [DisplayLine], isAligned: Bool) {
        self.text = text; self.revision = revision; self.lines = lines; self.isAligned = isAligned
    }
    public func text(in line: DisplayLine) -> String {
        (text as NSString).substring(with: line.range)
    }
    public var numberedText: String {
        lines.map { "[L\($0.id)] \(text(in: $0))" }.joined(separator: "\n")
    }
}

public enum IssueKind: String, Codable, CaseIterable, Sendable {
    case spelling, grammar, punctuation, capitalization
    public var title: String {
        switch self {
        case .spelling: "拼写"
        case .grammar: "语法"
        case .punctuation: "标点"
        case .capitalization: "大小写"
        }
    }
}

public struct ReviewIssue: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let revision: UUID
    public let lineID: Int
    public let start: Int
    public let length: Int
    public let quote: String
    public let kind: IssueKind
    public let suggestion: String
    public let explanation: String
    public var dismissed: Bool
    public var range: NSRange { NSRange(location: start, length: length) }
    public init(id: UUID = UUID(), revision: UUID, lineID: Int, start: Int, length: Int,
                quote: String, kind: IssueKind, suggestion: String, explanation: String, dismissed: Bool = false) {
        self.id = id; self.revision = revision; self.lineID = lineID; self.start = start; self.length = length
        self.quote = quote; self.kind = kind; self.suggestion = suggestion; self.explanation = explanation
        self.dismissed = dismissed
    }
}

public struct IssueProposal: Codable, Sendable {
    public let line: Int
    public let quote: String
    public let occurrence: Int
    public let kind: IssueKind
    public let suggestion: String
    public let explanation: String
    public init(line: Int, quote: String, occurrence: Int, kind: IssueKind, suggestion: String, explanation: String) {
        self.line = line; self.quote = quote; self.occurrence = occurrence; self.kind = kind
        self.suggestion = suggestion; self.explanation = explanation
    }
}

public enum ReviewRejectionReason: String, Codable, Sendable {
    case emptyQuote, invalidOccurrence, occurrenceOutOfBounds, unchangedSuggestion, metadataSuggestion, emptyExplanation, invalidLine, quoteNotFound
    public var title: String {
        switch self {
        case .emptyQuote: "模型没有引用原词"
        case .invalidOccurrence: "原词出现次数无效"
        case .occurrenceOutOfBounds: "模型给出的出现次数超出实际数量"
        case .unchangedSuggestion: "修改前后相同"
        case .metadataSuggestion: "建议混入了行号"
        case .emptyExplanation: "缺少修改原因"
        case .invalidLine: "模型给出的行号不存在"
        case .quoteNotFound: "引用与该行识别文本不一致"
        }
    }
}

public struct RejectedReviewIssue: Codable, Identifiable, Sendable {
    public let id: UUID
    public let proposal: IssueProposal
    public let reason: ReviewRejectionReason
    public init(proposal: IssueProposal, reason: ReviewRejectionReason) {
        id = UUID(); self.proposal = proposal; self.reason = reason
    }
}

public struct ReviewResult: Sendable {
    public let issues: [ReviewIssue]
    public let rejectedCount: Int
    public let rejections: [RejectedReviewIssue]
    public let recoveredOccurrences: [IssueProposal]
    public let recoveredLines: [IssueProposal]
    public let modelEvidence: ReviewModelEvidence?
    public init(issues: [ReviewIssue], rejectedCount: Int, rejections: [RejectedReviewIssue] = [], recoveredOccurrences: [IssueProposal] = [], recoveredLines: [IssueProposal] = [], modelEvidence: ReviewModelEvidence? = nil) {
        self.issues = issues; self.rejectedCount = rejectedCount; self.rejections = rejections
        self.recoveredOccurrences = recoveredOccurrences
        self.recoveredLines = recoveredLines
        self.modelEvidence = modelEvidence
    }
}

public enum IssueAnchoring {
    /// A quoted word is not an occurrence inside another word (i in finish,
    /// go in forgot). Punctuation quotes remain literal character matches.
    public static func quoteRanges(_ quote: String, in text: String) -> [NSRange] {
        guard !quote.isEmpty else { return [] }
        let ns = text as NSString
        func word(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "'" || character == "’" }
        let leftBoundary = quote.first.map { $0.isLetter || $0.isNumber } ?? false
        let rightBoundary = quote.last.map { $0.isLetter || $0.isNumber } ?? false
        var result: [NSRange] = [], cursor = 0
        while cursor < ns.length {
            let found = ns.range(of: quote, options: .literal, range: NSRange(location: cursor, length: ns.length - cursor))
            guard found.location != NSNotFound else { break }
            cursor = NSMaxRange(found)
            guard let range = Range(found, in: text) else { continue }
            if leftBoundary && range.lowerBound > text.startIndex && word(text[text.index(before: range.lowerBound)]) { continue }
            if rightBoundary && range.upperBound < text.endIndex && word(text[range.upperBound]) { continue }
            result.append(found)
        }
        return result
    }
    public static func relocatingUniqueWordQuotes(_ issues: [ReviewIssue], in transcript: Transcript) -> [ReviewIssue] {
        issues.map { issue in
            let matches = quoteRanges(issue.quote, in: transcript.text)
            guard !matches.contains(issue.range), matches.count == 1,
                  let line = transcript.lines.first(where: { $0.start <= matches[0].location && NSMaxRange(matches[0]) <= NSMaxRange($0.range) }) else { return issue }
            return ReviewIssue(id: issue.id, revision: issue.revision, lineID: line.id, start: matches[0].location,
                length: matches[0].length, quote: issue.quote, kind: issue.kind, suggestion: issue.suggestion,
                explanation: issue.explanation, dismissed: issue.dismissed)
        }
    }
    public static func anchor(_ proposals: [IssueProposal], to transcript: Transcript,
                              recoverUniqueOccurrence: Bool = false, recoverUniqueLine: Bool = false) -> ReviewResult {
        var issues: [ReviewIssue] = []
        var rejected: [RejectedReviewIssue] = []
        var recovered: [IssueProposal] = [], recoveredLines: [IssueProposal] = []
        func occurrences(_ quote: String, in text: NSString) -> [NSRange] {
            quoteRanges(quote, in: text as String)
        }
        for proposal in proposals {
            func reject(_ reason: ReviewRejectionReason) { rejected.append(.init(proposal: proposal, reason: reason)) }
            guard !proposal.quote.isEmpty else { reject(.emptyQuote); continue }
            guard proposal.occurrence > 0 else { reject(.invalidOccurrence); continue }
            guard proposal.suggestion != proposal.quote else { reject(.unchangedSuggestion); continue }
            guard !proposal.suggestion.contains("[L") else { reject(.metadataSuggestion); continue }
            guard !proposal.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reject(.emptyExplanation); continue }
            let suppliedLine = transcript.lines.first { $0.id == proposal.line }
            let local = suppliedLine.map { occurrences(proposal.quote, in: transcript.text(in: $0) as NSString) } ?? []
            var line = suppliedLine
            var found: NSRange?
            var occurrenceRecovered = false, lineRecovered = false
            if let suppliedLine, proposal.occurrence <= local.count {
                let match = local[proposal.occurrence - 1]
                found = NSRange(location: suppliedLine.start + match.location, length: match.length)
            } else if let suppliedLine, recoverUniqueOccurrence, local.count == 1 {
                found = NSRange(location: suppliedLine.start + local[0].location, length: local[0].length)
                occurrenceRecovered = true
            }
            if found == nil, recoverUniqueLine {
                let global = occurrences(proposal.quote, in: transcript.text as NSString)
                if global.count == 1, let actualLine = transcript.lines.first(where: {
                    $0.start <= global[0].location && NSMaxRange(global[0]) <= NSMaxRange($0.range)
                }), actualLine.id != proposal.line {
                    line = actualLine; found = global[0]; lineRecovered = true
                }
            }
            guard let found, let line else {
                reject(suppliedLine == nil ? .invalidLine : local.isEmpty ? .quoteNotFound : .occurrenceOutOfBounds); continue
            }
            guard !issues.contains(where: { $0.start == found.location && $0.length == found.length && $0.kind == proposal.kind }) else { continue }
            if occurrenceRecovered { recovered.append(proposal) }
            if lineRecovered { recoveredLines.append(proposal) }
            issues.append(ReviewIssue(revision: transcript.revision, lineID: line.id, start: found.location,
                length: found.length, quote: proposal.quote, kind: proposal.kind,
                suggestion: proposal.suggestion, explanation: proposal.explanation))
        }
        return ReviewResult(issues: issues, rejectedCount: rejected.count, rejections: rejected,
                            recoveredOccurrences: recovered, recoveredLines: recoveredLines)
    }
}

public struct OCRCandidate: Codable, Identifiable, Sendable {
    public let id: UUID
    public let attempt: Int
    public let transcript: Transcript
    public var score: Double?
    public let rawText: String?
    public let literalRepairs: [LiteralRepair]?
    public let wordVerification: WordVerificationSummary?
    public let readability: ReadabilityEvidence?
    public let uncertainLineIDs: [Int]?
    public let uncertainWordRects: [PageRect]?
    public var scoredSourceVersion: String?
    public init(attempt: Int, transcript: Transcript, score: Double? = nil, rawText: String? = nil, literalRepairs: [LiteralRepair]? = nil,
                wordVerification: WordVerificationSummary? = nil, uncertainLineIDs: [Int]? = nil, uncertainWordRects: [PageRect]? = nil,
                scoredSourceVersion: String? = nil, readability: ReadabilityEvidence? = nil) {
        id = UUID(); self.attempt = attempt; self.transcript = transcript; self.score = score
        self.rawText = rawText; self.literalRepairs = literalRepairs
        self.wordVerification = wordVerification; self.uncertainLineIDs = uncertainLineIDs
        self.uncertainWordRects = uncertainWordRects
        self.scoredSourceVersion = scoredSourceVersion
        self.readability = readability
    }
}

public enum PipelinePhase: String, Codable, Sendable {
    case queued, preparing, recognizing, verifyingWords, scoring, needsConfirmation, reviewing, complete, failed, cancelled
    public var title: String {
        switch self {
        case .queued: "等待处理"
        case .preparing: "正在处理照片"
        case .recognizing: "正在转写"
        case .verifyingWords: "正在逐词识别"
        case .scoring: "正在复核识别"
        case .needsConfirmation: "可继续审核"
        case .reviewing: "正在基础审核"
        case .complete: "审核完成"
        case .failed: "处理未完成"
        case .cancelled: "已暂停"
        }
    }
    public var isRunning: Bool { [.preparing, .recognizing, .verifyingWords, .scoring, .reviewing].contains(self) }
}

public enum QualityGate {
    public static func validScore(_ score: Double) -> Bool { score.isFinite && (0...1).contains(score) }
    /// A low whole-page score is renderer-dependent. Complete, stable literal
    /// evidence can finish recognition without repeatedly generating the same
    /// essay. These coverage limits are operational heuristics, not accuracy.
    public static func canProceed(score: Double, threshold: Double, verification: WordVerificationSummary?,
                                  readability: ReadabilityEvidence?) -> Bool {
        guard validScore(score), validScore(threshold) else { return false }
        if score >= threshold { return true }
        guard let verification, let readability, verification.totalRegions >= 10,
              verification.checkedRegions == verification.totalRegions,
              readability.totalRegions == verification.totalRegions,
              readability.evaluatedRegions == readability.totalRegions,
              verification.transcriptWords > 0,
              verification.locatedWords * 20 >= verification.transcriptWords * 19,
              verification.unresolvedRegions * 5 <= verification.totalRegions else { return false }
        return (readability.unreadableRegions + readability.unstableRegions) * 10 <= readability.totalRegions
    }
    public static func best(_ candidates: [OCRCandidate]) -> OCRCandidate? {
        candidates.filter { $0.score.map(validScore) ?? false }
            .max { ($0.score ?? -.infinity) < ($1.score ?? -.infinity) }
    }
}

public struct WordHint: Codable, Sendable {
    public let lineID: Int
    public let text: String
    public let rect: PageRect
    public let confidence: Double
    public init(lineID: Int, text: String, rect: PageRect, confidence: Double) {
        self.lineID = lineID; self.text = text; self.rect = rect; self.confidence = confidence
    }
}

public struct DisputedWord: Sendable {
    public let range: NSRange
    public let original: String
    public let hint: WordHint
}

public struct LiteralRepair: Codable, Sendable {
    public let original: String
    public let literal: String
    public let rect: PageRect
    public let originalScore: Double
    public let literalScore: Double
    public init(original: String, literal: String, rect: PageRect, originalScore: Double, literalScore: Double) {
        self.original = original; self.literal = literal; self.rect = rect
        self.originalScore = originalScore; self.literalScore = literalScore
    }
}

public enum LiteralVerification {
    /// Independent letter-count agreement is stronger evidence of a dropped or
    /// repeated letter than a whole-word classifier's language prior. For a
    /// same-length substitution, require independent agreement AND visual support.
    /// These are transcription heuristics, not a spelling dictionary or grammar fix.
    public static func independentPreference(original: String, isolated: String?, hint: String,
                                             originalScore: Double?, literalScore: Double?) -> String? {
        guard let isolated, isolated == hint, isolated != original else { return nil }
        let source = Array(original.lowercased().filter { !$0.isWhitespace })
        let literal = Array(isolated.lowercased().filter { !$0.isWhitespace })
        func subsequence(_ shorter: [Character], _ longer: [Character]) -> Bool {
            var index = 0
            for character in longer where index < shorter.count {
                if character == shorter[index] { index += 1 }
            }
            return index == shorter.count
        }
        if !source.isEmpty, !literal.isEmpty, source.count != literal.count,
           subsequence(source.count < literal.count ? source : literal, source.count < literal.count ? literal : source) {
            return "independent_letter_count"
        }
        if let originalScore, let literalScore,
           QualityGate.validScore(originalScore), QualityGate.validScore(literalScore),
           literalScore - originalScore >= 0.025, literalScore >= originalScore * 1.5 {
            return "independent_visual_agreement"
        }
        return nil
    }
    public static func disputedWords(_ transcript: Transcript, hints: [WordHint]) -> [DisputedWord] {
        guard transcript.isAligned else { return [] }
        let regex = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)*|[0-9]+")
        var result: [DisputedWord] = []
        for line in transcript.lines {
            let text = transcript.text(in: line) as NSString
            let words = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
            let source = hints.filter { $0.lineID == line.id }
            // Token insertion/deletion is an unresolved difference, never guessed into a replacement.
            guard words.count == source.count else { continue }
            for (word, hint) in zip(words, source) where hint.confidence >= 0.9 {
                let original = text.substring(with: word.range)
                if original != hint.text {
                    result.append(DisputedWord(range: NSRange(location: line.start + word.range.location, length: word.range.length), original: original, hint: hint))
                }
            }
        }
        return result
    }
    public static func prefersAlternative(originalScore: Double, alternativeScore: Double) -> Bool {
        QualityGate.validScore(originalScore) && QualityGate.validScore(alternativeScore)
            && alternativeScore >= 0.5 && alternativeScore - originalScore >= 0.05
    }
    public static func accepts(original: String, isolated: String, hint: String, originalScore: Double, literalScore: Double) -> Bool {
        isolated == hint && isolated != original
            && prefersAlternative(originalScore: originalScore, alternativeScore: literalScore)
    }
}

import Foundation

public enum TeacherResolution: String, Codable, Sendable { case annotation, keepOriginal }

public struct TeacherDecision: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public let issue: ReviewIssue
    public var resolution: TeacherResolution
    public var suggestion: String
    public var explanation: String
    public var date: Date
    public init(issue: ReviewIssue, resolution: TeacherResolution, suggestion: String? = nil, explanation: String? = nil) {
        id = UUID(); self.issue = issue; self.resolution = resolution
        self.suggestion = suggestion ?? issue.suggestion; self.explanation = explanation ?? issue.explanation; date = Date()
    }
    public func matches(_ candidate: ReviewIssue) -> Bool {
        issue.revision == candidate.revision && issue.range == candidate.range
            && issue.quote == candidate.quote && issue.suggestion == candidate.suggestion && issue.kind == candidate.kind
    }
    public func isAnchored(in transcript: Transcript) -> Bool {
        issue.revision == transcript.revision && issue.start >= 0 && issue.length > 0
            && NSMaxRange(issue.range) <= transcript.text.utf16.count
            && (transcript.text as NSString).substring(with: issue.range) == issue.quote
    }
    public var annotation: ReviewIssue {
        ReviewIssue(id: issue.id, revision: issue.revision, lineID: issue.lineID, start: issue.start,
            length: issue.length, quote: issue.quote, kind: issue.kind, suggestion: suggestion, explanation: explanation)
    }
}

/// Teacher judgments are a separate layer. Neither accepting nor dismissing a
/// suggestion changes the student's transcript or the model's original result.
public struct TeacherReview: Codable, Equatable, Sendable {
    public var decisions: [TeacherDecision] = []
    public var comment = ""
    public var completedAt: Date?
    public init() {}
    public var confirmed: [TeacherDecision] { decisions.filter { $0.resolution == .annotation } }
    public var discarded: [TeacherDecision] { decisions.filter { $0.resolution == .keepOriginal } }
    public func decision(for issue: ReviewIssue) -> TeacherDecision? { decisions.first { $0.matches(issue) } }
    public mutating func record(_ decision: TeacherDecision) {
        decisions.removeAll { $0.matches(decision.issue) }
        decisions.append(decision); completedAt = nil
    }
    public mutating func restore(_ issue: ReviewIssue) {
        decisions.removeAll { $0.matches(issue) }; completedAt = nil
    }
    public func pending(_ issues: [ReviewIssue]) -> [ReviewIssue] {
        issues.filter { decision(for: $0) == nil }.sorted { $0.start < $1.start }
    }
    public func annotations(in transcript: Transcript) -> [ReviewIssue] {
        decisions.filter { $0.resolution == .annotation && $0.isAnchored(in: transcript) }.map(\.annotation)
    }
}

public struct ReviewSentence: Sendable {
    public let text: String
    public let quoteRange: NSRange
    public static func context(for issue: ReviewIssue, in transcript: Transcript) -> Self? {
        guard issue.revision == transcript.revision, issue.start >= 0, issue.length > 0,
              NSMaxRange(issue.range) <= transcript.text.utf16.count,
              (transcript.text as NSString).substring(with: issue.range) == issue.quote else { return nil }
        let text = transcript.text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        var sentences: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { _, range, _, _ in
            sentences.append(NSRange(range, in: text))
        }
        guard let range = sentences.first(where: { NSIntersectionRange($0, issue.range) == issue.range }) else { return nil }
        return Self(text: (text as NSString).substring(with: range),
            quoteRange: NSRange(location: issue.start - range.location, length: issue.length))
    }
}

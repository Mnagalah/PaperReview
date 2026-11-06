import Foundation
import Testing
@testable import PaperReviewCore

private func reviewFixture() -> (Transcript, [ReviewIssue]) {
    let transcript = LineAlignment.fallback("Last weekend, I have fun.\nThe wether is suny.")
    let proposals: [IssueProposal] = [
        .init(line: 1, quote: "have", occurrence: 1, kind: .grammar, suggestion: "had", explanation: "过去时"),
        .init(line: 2, quote: "suny", occurrence: 1, kind: .spelling, suggestion: "sunny", explanation: "缺少 n")
    ]
    return (transcript, IssueAnchoring.anchor(proposals, to: transcript).issues)
}

@Test func teacherDecisionsAreSeparateFromTheTranscriptAndMachineSuggestions() throws {
    let (transcript, issues) = reviewFixture()
    let original = transcript.text
    var review = TeacherReview()
    review.record(.init(issue: issues[0], resolution: .annotation))
    review.record(.init(issue: issues[1], resolution: .keepOriginal))
    #expect(review.pending(issues).isEmpty)
    #expect(review.confirmed.map(\.issue.id) == [issues[0].id])
    #expect(review.discarded.map(\.issue.id) == [issues[1].id])
    #expect(review.annotations(in: transcript).count == 1)
    #expect(transcript.text == original)
    #expect(!issues.contains { $0.dismissed })
    let restored = try JSONDecoder().decode(TeacherReview.self, from: JSONEncoder().encode(review))
    #expect(restored == review)
    review.restore(issues[0])
    #expect(review.pending(issues).map(\.id) == [issues[0].id])
}

@Test func changedRevisionKeepsHistoryButNeverHighlightsAnOldAnchor() {
    let (transcript, issues) = reviewFixture()
    var review = TeacherReview()
    review.record(.init(issue: issues[0], resolution: .annotation))
    let revised = LineAlignment.fallback(transcript.text.replacingOccurrences(of: "have", with: "had"))
    #expect(review.annotations(in: revised).isEmpty)
    #expect(review.decisions.count == 1)
    let newIssue = ReviewIssue(revision: revised.revision, lineID: 1, start: issues[0].start, length: 3,
        quote: "had", kind: .grammar, suggestion: "have", explanation: "fixture")
    #expect(review.pending([newIssue]).count == 1)
    review.completedAt = Date()
    review.record(.init(issue: newIssue, resolution: .keepOriginal))
    #expect(review.completedAt == nil)
}

@Test func regeneratedIssueIDsRetainDecisionsOnlyForTheSameMeaningAndRevision() {
    let (_, issues) = reviewFixture()
    var review = TeacherReview()
    review.record(.init(issue: issues[0], resolution: .annotation, suggestion: "had", explanation: "教师说明"))
    let source = issues[0]
    let regenerated = ReviewIssue(revision: source.revision, lineID: source.lineID, start: source.start,
        length: source.length, quote: source.quote, kind: source.kind, suggestion: source.suggestion, explanation: source.explanation)
    #expect(review.decision(for: regenerated) != nil)
    let different = ReviewIssue(revision: source.revision, lineID: source.lineID, start: source.start,
        length: source.length, quote: source.quote, kind: source.kind, suggestion: "will have", explanation: source.explanation)
    #expect(review.decision(for: different) == nil)
}

@Test func sentenceContextSpansPhotoLineBreaksAndPreservesUTF16Offsets() throws {
    let transcript = LineAlignment.fallback("😀 I\nfeeled happy. Another sentence.")
    let start = (transcript.text as NSString).range(of: "feeled").location
    let issue = ReviewIssue(revision: transcript.revision, lineID: 2, start: start, length: 6,
        quote: "feeled", kind: .spelling, suggestion: "felt", explanation: "fixture")
    let sentence = try #require(ReviewSentence.context(for: issue, in: transcript))
    #expect(sentence.text.contains("I feeled happy."))
    #expect(!sentence.text.contains("Another"))
    #expect((sentence.text as NSString).substring(with: sentence.quoteRange) == "feeled")
    let stale = ReviewIssue(revision: UUID(), lineID: issue.lineID, start: issue.start, length: issue.length,
        quote: issue.quote, kind: issue.kind, suggestion: issue.suggestion, explanation: issue.explanation)
    #expect(ReviewSentence.context(for: stale, in: transcript) == nil)
}

@Test func teacherExportKeepsTheSourceAndDistinguishesAnnotationsFromPendingSuggestions() {
    let (transcript, issues) = reviewFixture()
    var review = TeacherReview()
    review.record(.init(issue: issues[0], resolution: .annotation))
    review.comment = "注意过去时。"
    let output = MarkdownExport.annotated(transcript, issues: issues, humanConfirmed: false, teacherReview: review)
    #expect(output.hasPrefix(MarkdownExport.original(transcript)))
    #expect(output.contains("## 批注") && output.contains("## 待确认批注"))
    #expect(!output.contains("教师批注") && !output.contains("批阅状态"))
    #expect(output.contains("注意过去时。"))
    let revised = LineAlignment.fallback(transcript.text)
    let stale = MarkdownExport.annotated(revised, issues: [], humanConfirmed: true, teacherReview: review)
    #expect(stale.contains("位置待确认"))
    review.record(.init(issue: issues[1], resolution: .keepOriginal))
    review.completedAt = Date()
    let completed = MarkdownExport.annotated(transcript, issues: issues, humanConfirmed: false, teacherReview: review)
    #expect(completed.hasPrefix(MarkdownExport.original(transcript)))
    #expect(completed.contains("## 已放弃的建议"))
    #expect(!completed.contains("## 待确认批注") && !completed.contains("批阅状态"))
}

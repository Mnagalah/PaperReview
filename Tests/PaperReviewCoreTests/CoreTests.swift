import Foundation
import Testing
@testable import PaperReviewCore

@Test func studentErrorsAreNeverRewritten() {
    let text = "My freind go to school.\n\nShe don't likes apple.\n"
    let hints = [TextHint(text: "My friend goes to school.", rect: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.04)),
                 TextHint(text: "She doesn't like apples.", rect: .init(x: 0.1, y: 0.4, width: 0.6, height: 0.04))]
    let result = LineAlignment.makeTranscript(text: text, hints: hints)
    #expect(result.text == text)
    #expect(result.isAligned)
    #expect(result.lines.map { result.text(in: $0) }.joined() == text)
}

@Test func wordQuotesCannotAnchorInsideAnotherWord() {
    let transcript = LineAlignment.fallback("I finish my homework, i go home.")
    let result = IssueAnchoring.anchor([.init(line: 1, quote: "i", occurrence: 2, kind: .capitalization,
        suggestion: "I", explanation: "代词大写")], to: transcript, recoverUniqueOccurrence: true)
    #expect(result.issues.count == 1)
    #expect(result.issues[0].start == (transcript.text as NSString).range(of: ", i").location + 2)
    #expect(IssueAnchoring.quoteRanges("go", in: "I forgot to go.").count == 1)
    #expect(IssueAnchoring.quoteRanges(",", in: "a,b,c").count == 2)
}

@Test func aSavedSubwordMarkCanRecoverOneActualWholeWordWithoutChangingText() {
    let transcript = LineAlignment.fallback("i finish my homework.")
    let wrong = ReviewIssue(revision: transcript.revision, lineID: 1, start: 3, length: 1, quote: "i", kind: .capitalization,
        suggestion: "I", explanation: "代词大写")
    let fixed = IssueAnchoring.relocatingUniqueWordQuotes([wrong], in: transcript)
    #expect(fixed[0].start == 0)
    #expect(fixed[0].id == wrong.id)
    #expect(transcript.text == "i finish my homework.")
}

@Test func unmatchedVisionDoesNotInventWords() {
    let text = "I goed home."
    let result = LineAlignment.makeTranscript(text: text, hints: [.init(text: "Completely unrelated xyz", rect: .init(x: 0, y: 0, width: 1, height: 0.1))])
    #expect(!result.isAligned)
    #expect(result.text == text)
    #expect(result.lines.map { result.text(in: $0) }.joined() == text)
}

@Test func fallbackWrapsLongTextAndRetainsEveryCharacter() {
    let text = "👩🏽‍🏫 " + String(repeating: "hello freind ", count: 80) + "\n\nEnd."
    let result = LineAlignment.fallback(text)
    #expect(result.lines.count > 10)
    #expect(result.lines.map { result.text(in: $0) }.joined() == text)
}

@Test func anchorUsesLineAndOccurrenceNotFirstGlobalMatch() {
    let result = LineAlignment.fallback("go go\nShe go home.")
    let review = IssueAnchoring.anchor([
        .init(line: 1, quote: "go", occurrence: 2, kind: .grammar, suggestion: "goes", explanation: "示例"),
        .init(line: 2, quote: "go", occurrence: 1, kind: .grammar, suggestion: "goes", explanation: "主谓一致")
    ], to: result)
    #expect(review.issues.map(\.start) == [3, 10])
    #expect(review.rejectedCount == 0)
    #expect(result.text == "go go\nShe go home.")
}

@Test func hallucinatedOrChangedQuotesAreRejected() {
    let transcript = LineAlignment.fallback("My freind is here.")
    let result = IssueAnchoring.anchor([
        .init(line: 1, quote: "friend", occurrence: 1, kind: .spelling, suggestion: "friend", explanation: "不存在的引用"),
        .init(line: 99, quote: "freind", occurrence: 1, kind: .spelling, suggestion: "friend", explanation: "不存在的行"),
        .init(line: 1, quote: "", occurrence: 1, kind: .grammar, suggestion: "a", explanation: "空引用")
    ], to: transcript)
    #expect(result.issues.isEmpty)
    #expect(result.rejectedCount == 3)
}

@Test func utf16OffsetsKeepEmojiAndCurlyQuotesIntact() {
    let transcript = LineAlignment.fallback("😀 I dont know.")
    let result = IssueAnchoring.anchor([.init(line: 1, quote: "dont", occurrence: 1, kind: .spelling, suggestion: "don't", explanation: "缺少撇号")], to: transcript)
    #expect(result.issues.first?.start == 5)
    #expect((transcript.text as NSString).substring(with: result.issues[0].range) == "dont")
}

@Test func jevBestExcludesInvalidAndUnscoredCandidates() {
    let transcript = LineAlignment.fallback("abc")
    let candidates = [OCRCandidate(attempt: 1, transcript: transcript, score: 0.8),
                      OCRCandidate(attempt: 2, transcript: transcript, score: .nan),
                      OCRCandidate(attempt: 3, transcript: transcript, score: -1)]
    #expect(QualityGate.best(candidates)?.attempt == 1)
    #expect(QualityGate.best([OCRCandidate(attempt: 1, transcript: transcript)]) == nil)
}

@Test func reviewedMarkdownKeepsOriginalAndSkipsStaleAnnotations() {
    let transcript = LineAlignment.fallback("I goed home.")
    let issue = ReviewIssue(revision: transcript.revision, lineID: 1, start: 2, length: 4, quote: "goed", kind: .grammar, suggestion: "went", explanation: "过去式")
    let stale = ReviewIssue(revision: UUID(), lineID: 1, start: 2, length: 4, quote: "goed", kind: .grammar, suggestion: "walked", explanation: "旧版本")
    let export = MarkdownExport.annotated(transcript, issues: [issue, stale], humanConfirmed: false)
    #expect(export.hasPrefix("I goed home.\n"))
    #expect(export.contains("went"))
    #expect(!export.contains("walked"))
}

@Test func secondaryRecognitionFlagsCorrectionButNeverSubstitutesIt() {
    let hints = [TextHint(text: "a beautifull bird", rect: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.05), confidence: 1)]
    let transcript = LineAlignment.makeTranscript(text: "a beautiful bird", hints: hints)
    #expect(LineAlignment.uncertainLines(transcript, hints: hints) == [1])
    #expect(transcript.text == "a beautiful bird")
    let unreliable = [TextHint(text: "a completely different bird", rect: hints[0].rect, confidence: 0.3)]
    #expect(LineAlignment.uncertainLines(transcript, hints: unreliable).isEmpty)
}

@Test func literalRepairRequiresIndependentWordOCRAndVisualPreference() {
    #expect(LiteralVerification.accepts(original: "beautiful", isolated: "beautifull", hint: "beautifull", originalScore: 0.022, literalScore: 0.897))
    #expect(!LiteralVerification.accepts(original: "beautiful", isolated: "beautifull", hint: "beautiful", originalScore: 0.022, literalScore: 0.897))
    #expect(!LiteralVerification.accepts(original: "beautiful", isolated: "beautifull", hint: "beautifull", originalScore: 0.4, literalScore: 0.4))
}

@Test func metadataCannotBecomeACorrection() {
    let transcript = LineAlignment.fallback("I goed home.")
    let result = IssueAnchoring.anchor([.init(line: 1, quote: "goed", occurrence: 1, kind: .grammar, suggestion: "[L1] - [L1]", explanation: "无效输出")], to: transcript)
    #expect(result.issues.isEmpty)
    #expect(result.rejectedCount == 1)
}

@Test func markdownPreservesSourceWrapsAndParagraphsWithoutCorrectingWords() {
    let text = "I goed home.\nMy freind came.\nA new paragraph."
    let ns = text as NSString
    let transcript = Transcript(text: text, lines: [
        .init(id: 1, start: 0, length: 13, rect: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.03)),
        .init(id: 2, start: 13, length: 16, rect: .init(x: 0.1, y: 0.15, width: 0.8, height: 0.03)),
        .init(id: 3, start: 29, length: ns.length - 29, rect: .init(x: 0.1, y: 0.35, width: 0.8, height: 0.03))
    ], isAligned: true)
    let markdown = MarkdownExport.original(transcript)
    #expect(markdown.contains("goed"))
    #expect(markdown.contains("freind"))
    #expect(markdown.contains("  \n"))
    #expect(markdown.contains("\n\n"))
}

@Test func nearTiedInconsistentWordScoresCannotChangeTheOriginal() {
    #expect(!LiteralVerification.prefersAlternative(originalScore: 0.03835, alternativeScore: 0.04411))
    #expect(LiteralVerification.prefersAlternative(originalScore: 0.02238, alternativeScore: 0.89675))
}

@Test func rejectedSuggestionsKeepTheActualCauseAndOriginalProposal() {
    let transcript = LineAlignment.fallback("My freind is here.")
    let proposals: [IssueProposal] = [
        .init(line: 1, quote: "freind", occurrence: 1, kind: .spelling, suggestion: "freind", explanation: "不应改动"),
        .init(line: 99, quote: "freind", occurrence: 1, kind: .spelling, suggestion: "friend", explanation: "拼写"),
        .init(line: 1, quote: "friend", occurrence: 1, kind: .spelling, suggestion: "friends", explanation: "引用不存在"),
        .init(line: 1, quote: "freind", occurrence: 1, kind: .spelling, suggestion: "friend", explanation: "")
    ]
    let result = IssueAnchoring.anchor(proposals, to: transcript)
    #expect(result.rejectedCount == 4)
    #expect(result.rejections.map(\.reason) == [.unchangedSuggestion, .invalidLine, .quoteNotFound, .emptyExplanation])
    #expect(result.rejections.map { $0.proposal.quote } == proposals.map(\.quote))
    #expect(transcript.text == "My freind is here.")
}

@Test func uniqueExactQuoteRecoversModelCountingErrorsWithoutFuzzyMatching() {
    let transcript = LineAlignment.fallback("The suny day.\nI help they.\nI feeled tired.")
    let proposals: [IssueProposal] = [
        .init(line: 1, quote: "suny", occurrence: 2, kind: .spelling, suggestion: "sunny", explanation: "拼写"),
        .init(line: 2, quote: "help they", occurrence: 4, kind: .grammar, suggestion: "help them", explanation: "宾格"),
        .init(line: 3, quote: "feeld", occurrence: 5, kind: .grammar, suggestion: "felt", explanation: "过去式")
    ]
    let strict = IssueAnchoring.anchor(proposals, to: transcript)
    #expect(strict.rejections.map(\.reason) == [.occurrenceOutOfBounds, .occurrenceOutOfBounds, .quoteNotFound])
    let result = IssueAnchoring.anchor(proposals, to: transcript, recoverUniqueOccurrence: true)
    #expect(result.issues.map(\.quote) == ["suny", "help they"])
    #expect(result.recoveredOccurrences.map(\.occurrence) == [2, 4])
    #expect(result.rejections.map(\.reason) == [.quoteNotFound])
    #expect(transcript.text == "The suny day.\nI help they.\nI feeled tired.")
}

@Test func repeatedQuoteCannotGuessWhichOccurrenceTheModelMeant() {
    let transcript = LineAlignment.fallback("go go")
    let result = IssueAnchoring.anchor([.init(line: 1, quote: "go", occurrence: 3, kind: .grammar,
        suggestion: "goes", explanation: "测试")], to: transcript, recoverUniqueOccurrence: true)
    #expect(result.issues.isEmpty)
    #expect(result.rejections.first?.reason == .occurrenceOutOfBounds)
    #expect(result.recoveredOccurrences.isEmpty)
}

@Test func wrongLineCanRecoverOnlyOneExactUnambiguousQuote() {
    let transcript = LineAlignment.fallback("English is good.\nI can developing my skills.\nI read read.")
    let proposals: [IssueProposal] = [
        .init(line: 1, quote: "developing", occurrence: 1, kind: .grammar, suggestion: "develop", explanation: "情态动词"),
        .init(line: 1, quote: "read", occurrence: 1, kind: .grammar, suggestion: "reading", explanation: "无法确定哪一个"),
        .init(line: 2, quote: "developping", occurrence: 1, kind: .spelling, suggestion: "developing", explanation: "原文不存在")
    ]
    let result = IssueAnchoring.anchor(proposals, to: transcript, recoverUniqueOccurrence: true, recoverUniqueLine: true)
    #expect(result.issues.count == 1)
    #expect(result.issues[0].lineID == 2)
    #expect(result.issues[0].quote == "developing")
    #expect(result.recoveredLines.count == 1)
    #expect(result.rejectedCount == 2)
}

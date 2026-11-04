import Foundation
import Testing
@testable import PaperReviewCore

private func reading(_ isolated: String? = "suny", source: String? = nil,
                     checked: Bool? = false, anchored: Bool = true) -> WordCheck {
    let region = WordRegion(id: 1, lineID: 1, rect: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.05),
        hint: "suny", original: anchored ? "suny" : nil, start: anchored ? 0 : nil,
        length: anchored ? 4 : nil, sourceWordCount: 1)
    var check = WordCheck(region: region, isolated: isolated, sourceReading: source, sourceChecked: checked)
    check.selected = "suny"
    // Deliberately mark every word unresolved: geometry status is not difficulty.
    check.unresolved = true
    return check
}

@Test func readableMisspellingsAndUnanchoredWordsDoNotMeanPoorHandwriting() {
    let checks = Array(repeating: reading(anchored: false), count: 20)
    let evidence = ReadabilityEvidence(checks: checks, totalRegions: 20)
    #expect(evidence.evaluatedRegions == 20)
    #expect(evidence.unreadableRegions == 0 && evidence.unstableRegions == 0)
    #expect(!evidence.isPoor)
}

@Test func unreadableAndConflictingImageReadingsCanTriggerTheSingleWarning() {
    let checks = Array(repeating: reading(nil, checked: true), count: 3)
        + Array(repeating: reading("suny", source: "sony", checked: true), count: 2)
        + Array(repeating: reading(), count: 5)
    let evidence = ReadabilityEvidence(checks: checks, totalRegions: 10)
    #expect(evidence.unreadableRegions == 3 && evidence.unstableRegions == 2)
    #expect(evidence.isPoor)
    #expect(!ReadabilityEvidence(checks: Array(checks.dropLast()), totalRegions: 10).isPoor)
    #expect(!ReadabilityEvidence(checks: Array(checks.prefix(5)), totalRegions: 5).isPoor)
}

@Test func legacyMissingEvidenceAndMinorDifferencesDoNotTriggerTheWarning() {
    #expect(!ReadabilityEvidence(checks: Array(repeating: reading(nil, checked: nil), count: 20), totalRegions: 20).isPoor)
    let checks = Array(repeating: reading("suny", source: "suny", checked: true), count: 16)
        + Array(repeating: reading(nil, source: "suny", checked: true), count: 4)
    #expect(!ReadabilityEvidence(checks: checks, totalRegions: 20).isPoor)
}

@Test func readabilityEvidencePersistsWithTheCandidateAndOldCandidatesStillDecode() throws {
    let transcript = LineAlignment.fallback("The wether is suny.")
    let evidence = ReadabilityEvidence(checks: Array(repeating: reading(nil, checked: true), count: 10), totalRegions: 10)
    let candidate = OCRCandidate(attempt: 1, transcript: transcript, score: 0.01, readability: evidence)
    let decoder = JSONDecoder(), encoder = JSONEncoder()
    let restored = try decoder.decode(OCRCandidate.self, from: encoder.encode(candidate))
    #expect(restored.readability == evidence)
    let legacy = OCRCandidate(attempt: 1, transcript: transcript, score: 0.01)
    let old = try decoder.decode(OCRCandidate.self, from: encoder.encode(legacy))
    #expect(old.readability == nil)
}

@Test func ordinaryHomeworkDoesNotNeedManualCheckingBecauseOfSpellingOrALowJevScore() {
    let stable = ReadabilityEvidence(checks: Array(repeating: reading(), count: 30), totalRegions: 30)
    let unlocated = WordVerificationSummary(totalRegions: 30, checkedRegions: 30,
        transcriptWords: 30, locatedWords: 0, unresolvedRegions: 30)
    #expect(!stable.needsAssistance(verification: unlocated, score: 0.01))
    let fewDifferences = ReadabilityEvidence(checks: Array(repeating: reading(nil, checked: true), count: 5)
        + Array(repeating: reading(), count: 51), totalRegions: 56)
    #expect(!fewDifferences.needsAssistance(verification: nil, score: 0.01))
}

@Test func difficultHomeworkCanOfferManualAssistanceWithoutTreatingMissingEvidenceAsFailure() {
    let checks = Array(repeating: reading(nil, checked: true), count: 1)
        + Array(repeating: reading("suny", source: "sony", checked: true), count: 7)
        + Array(repeating: reading(), count: 22)
    let evidence = ReadabilityEvidence(checks: checks, totalRegions: 30)
    #expect(evidence.needsAssistance(verification: nil, score: 0.04))
    let unlocated = WordVerificationSummary(totalRegions: 30, checkedRegions: 30,
        transcriptWords: 30, locatedWords: 10, unresolvedRegions: 20)
    #expect(evidence.needsAssistance(verification: unlocated, score: 0.5))
    let located = WordVerificationSummary(totalRegions: 30, checkedRegions: 30,
        transcriptWords: 30, locatedWords: 29, unresolvedRegions: 1)
    #expect(!evidence.needsAssistance(verification: located, score: 0.5))
    let incomplete = ReadabilityEvidence(checks: Array(checks.dropLast()), totalRegions: 30)
    #expect(!incomplete.needsAssistance(verification: unlocated, score: 0.01))
}

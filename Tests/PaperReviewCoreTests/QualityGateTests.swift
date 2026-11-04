import Testing
@testable import PaperReviewCore

private func coverage(checked: Int = 50, located: Int = 51, unresolved: Int = 10) -> WordVerificationSummary {
    .init(totalRegions: 50, checkedRegions: checked, transcriptWords: 52, locatedWords: located, unresolvedRegions: unresolved)
}
private func readings(unstable: Int, completed: Int = 50) -> ReadabilityEvidence {
    let region = WordRegion(id: 1, lineID: 1, rect: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.05),
        hint: "suny", original: "suny", start: 0, length: 4, sourceWordCount: 1)
    let checks = (0..<completed).map { i in
        WordCheck(region: region, isolated: "suny", sourceReading: i < unstable ? "sony" : "suny", sourceChecked: true)
    }
    return ReadabilityEvidence(checks: checks, totalRegions: 50)
}

@Test func stableNormalHomeworkContinuesAfterBothOCRRoundsAndJevWithoutRedundantRetries() {
    #expect(QualityGate.canProceed(score: 0.02, threshold: 0.5,
        verification: coverage(), readability: readings(unstable: 4)))
    #expect(QualityGate.canProceed(score: 0.8, threshold: 0.5, verification: nil, readability: nil))
}

@Test func missingOrUnstableLiteralEvidenceStillRequiresTheLowScoreRetryPath() {
    #expect(!QualityGate.canProceed(score: 0.02, threshold: 0.5, verification: nil, readability: nil))
    #expect(!QualityGate.canProceed(score: 0.02, threshold: 0.5, verification: coverage(checked: 49), readability: readings(unstable: 4)))
    #expect(!QualityGate.canProceed(score: 0.02, threshold: 0.5, verification: coverage(located: 48), readability: readings(unstable: 4)))
    #expect(!QualityGate.canProceed(score: 0.02, threshold: 0.5, verification: coverage(unresolved: 11), readability: readings(unstable: 4)))
    #expect(!QualityGate.canProceed(score: 0.02, threshold: 0.5, verification: coverage(), readability: readings(unstable: 6)))
    #expect(!QualityGate.canProceed(score: 0.02, threshold: 0.5, verification: coverage(), readability: readings(unstable: 4, completed: 49)))
    #expect(!QualityGate.canProceed(score: .nan, threshold: 0.5, verification: coverage(), readability: readings(unstable: 4)))
}

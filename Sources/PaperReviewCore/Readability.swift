import Foundation

/// Recognition difficulty on the supplied photo, not spelling errors or a
/// handwriting grade. Neither alignment failures nor Jev scores alone can
/// classify a photo as difficult.
public struct ReadabilityEvidence: Codable, Equatable, Sendable {
    public let version: String
    public let totalRegions: Int
    public let evaluatedRegions: Int
    public let unreadableRegions: Int
    public let unstableRegions: Int

    public init(checks: [WordCheck], totalRegions: Int) {
        version = "word-readability-v1"
        self.totalRegions = totalRegions
        // A nil sourceChecked denotes an old record that did not implement
        // source-view verification. Do not count its missing data as failure.
        let evaluated = checks.filter { $0.sourceChecked != nil }
        evaluatedRegions = evaluated.count
        unreadableRegions = evaluated.filter {
            $0.sourceChecked == true && $0.isolated == nil && $0.sourceReading == nil
        }.count
        unstableRegions = evaluated.filter {
            $0.sourceChecked == true && $0.isolated != $0.sourceReading
        }.count
    }

    /// A conservative first-version warning: the full word pass has finished,
    /// at least ten regions were inspected, and half remain unreadable/unstable.
    /// This threshold is a product heuristic, not a calibrated error rate.
    public var isPoor: Bool {
        totalRegions >= 10 && evaluatedRegions == totalRegions
            && unreadableRegions + unstableRegions >= (totalRegions + 1) / 2
    }

    /// Difficulty warning, not an automatic proofreading gate. A less extreme
    /// word-reading disagreement also needs independent page/anchoring evidence.
    public func needsAssistance(verification: WordVerificationSummary?, score: Double?) -> Bool {
        if isPoor { return true }
        guard totalRegions >= 10, evaluatedRegions == totalRegions,
              unreadableRegions + unstableRegions >= (totalRegions + 3) / 4 else { return false }
        if let score, QualityGate.validScore(score), score < 0.10 { return true }
        guard let verification, verification.totalRegions == totalRegions,
              verification.checkedRegions == totalRegions, verification.transcriptWords >= 10 else { return false }
        return verification.locatedWords * 2 < verification.transcriptWords
    }
}

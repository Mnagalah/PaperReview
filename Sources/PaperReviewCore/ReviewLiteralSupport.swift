import Foundation

public enum ReviewLiteralSupport {
    /// Literal support for displaying a suggestion without a recognition warning.
    /// A false result classifies OCR risk; current UI still lists a valid text anchor.
    /// Two independent image readings can support a word inside an unresolved group.
    public static func canAnnotate(_ issue: ReviewIssue, transcript: Transcript, inventory: WordInventory,
                                   uncertainRects: [PageRect], checks: [WordCheck], humanConfirmed: Bool = false) -> Bool {
        guard issue.revision == transcript.revision else { return false }
        if humanConfirmed { return true }
        guard !inventory.unlocatedRanges.contains(where: { NSIntersectionRange($0, issue.range).length > 0 }) else { return false }
        let original = transcript.text as NSString
        for region in inventory.regions where uncertainRects.contains(region.rect) {
            guard let range = region.range else { continue }
            let overlap = NSIntersectionRange(range, issue.range)
            guard overlap.length > 0 else { continue }
            guard let check = checks.first(where: { $0.region.rect == region.rect && $0.region.hint == region.hint }),
                  check.sourceChecked != nil else { return false }
            let quote = original.substring(with: overlap).trimmingCharacters(in: .whitespacesAndNewlines)
            if quote.isEmpty { continue }
            let readings = [check.isolated, check.sourceChecked == true ? check.sourceReading : nil,
                            WordAlignment.lexicalReading(check.region.hint)]
            let supported = readings.compactMap { $0 }.filter { !IssueAnchoring.quoteRanges(quote, in: $0).isEmpty }.count
            guard supported >= 2 else { return false }
        }
        return true
    }
}

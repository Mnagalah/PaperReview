import Foundation
import Testing
@testable import PaperReviewCore

private func proposal(_ quote: String, in transcript: Transcript) -> ReviewIssue {
    let range = (transcript.text as NSString).range(of: quote)
    return ReviewIssue(revision: transcript.revision, lineID: 1, start: range.location, length: range.length,
        quote: quote, kind: .grammar, suggestion: "replacement", explanation: "测试定位。")
}

@Test func oneFailedCropDoesNotSuppressAWordSupportedByTwoOtherImageReadings() throws {
    let text = "we go and have a picnic."
    let transcript = Transcript(text: text, lines: [.init(id: 1, start: 0, length: text.utf16.count,
        rect: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.05))], isAligned: true)
    let hints = [WordHint(lineID: 1, text: "go", rect: .init(x: 0.2, y: 0.1, width: 0.1, height: 0.05), confidence: 1),
        WordHint(lineID: 1, text: "havea", rect: .init(x: 0.5, y: 0.1, width: 0.2, height: 0.05), confidence: 1)]
    let inventory = WordAlignment.inventory(transcript, hints: hints)
    let go = try #require(inventory.regions.first { $0.original == "go" })
    let have = try #require(inventory.regions.first { $0.original == "have a" })
    let checks = [WordCheck(region: go, isolated: nil, sourceReading: "go", sourceChecked: true),
                  WordCheck(region: have, isolated: "have", sourceReading: "have", sourceChecked: true)]
    let rects = [go.rect, have.rect]
    #expect(ReviewLiteralSupport.canAnnotate(proposal("go", in: transcript), transcript: transcript, inventory: inventory, uncertainRects: rects, checks: checks))
    #expect(ReviewLiteralSupport.canAnnotate(proposal("have", in: transcript), transcript: transcript, inventory: inventory, uncertainRects: rects, checks: checks))
    #expect(!ReviewLiteralSupport.canAnnotate(proposal("have a", in: transcript), transcript: transcript, inventory: inventory, uncertainRects: rects, checks: checks))
    #expect(!ReviewLiteralSupport.canAnnotate(proposal("we", in: transcript), transcript: transcript, inventory: inventory, uncertainRects: rects, checks: checks))
    #expect(!ReviewLiteralSupport.canAnnotate(proposal("go", in: transcript), transcript: transcript, inventory: inventory, uncertainRects: rects, checks: []))
}

@Test func unsupportedSelectedSpellingAndUnknownLegacyEvidenceRemainDeferred() throws {
    let text = "clean"
    let transcript = Transcript(text: text, lines: [.init(id: 1, start: 0, length: 5,
        rect: .init(x: 0.1, y: 0.1, width: 0.4, height: 0.05))], isAligned: true)
    let hint = WordHint(lineID: 1, text: "chean", rect: .init(x: 0.1, y: 0.1, width: 0.4, height: 0.05), confidence: 1)
    let inventory = WordAlignment.inventory(transcript, hints: [hint])
    let region = try #require(inventory.regions.first)
    for check in [WordCheck(region: region, isolated: "chean", sourceReading: "chean", sourceChecked: true),
                  WordCheck(region: region, isolated: "clean", sourceReading: "clean", sourceChecked: nil)] {
        #expect(!ReviewLiteralSupport.canAnnotate(proposal(text, in: transcript), transcript: transcript, inventory: inventory,
            uncertainRects: [region.rect], checks: [check]))
    }
}

@Test func manualSourceConfirmationAllowsDifficultTextButNeverStaleRevisions() {
    let transcript = LineAlignment.fallback("I go home.")
    let inventory = WordAlignment.inventory(transcript, hints: [])
    let issue = proposal("go", in: transcript)
    #expect(!ReviewLiteralSupport.canAnnotate(issue, transcript: transcript, inventory: inventory, uncertainRects: [], checks: []))
    #expect(ReviewLiteralSupport.canAnnotate(issue, transcript: transcript, inventory: inventory, uncertainRects: [], checks: [], humanConfirmed: true))
    let changed = LineAlignment.fallback(transcript.text)
    #expect(!ReviewLiteralSupport.canAnnotate(issue, transcript: changed, inventory: inventory, uncertainRects: [], checks: [], humanConfirmed: true))
}

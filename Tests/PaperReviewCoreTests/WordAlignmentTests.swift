import Foundation
import Testing
@testable import PaperReviewCore

private func wordHints(_ texts: [String], line: Int = 1) -> [WordHint] {
    texts.enumerated().map { index, text in
        WordHint(lineID: line, text: text, rect: .init(x: Double(index) * 0.04, y: 0.2, width: 0.035, height: 0.04), confidence: 1)
    }
}
private func aligned(_ text: String) -> Transcript {
    Transcript(text: text, lines: [.init(id: 1, start: 0, length: (text as NSString).length,
        rect: .init(x: 0, y: 0.2, width: 1, height: 0.04))], isAligned: true)
}

@Test func wordRoundIncludesAgreementAndWordsBeyondTwelve() {
    // Use alphabetic tokens: the inventory uses actual lexical spans, not split identifiers.
    let text = Array(repeating: "sunny", count: 20).joined(separator: " ")
    let inventory = WordAlignment.inventory(aligned(text), hints: wordHints(Array(repeating: "sunny", count: 20)))
    #expect(inventory.regions.count == 20)
    #expect(inventory.transcriptWords == 20)
    #expect(inventory.locatedWords == 20)
    #expect(inventory.regions.last?.original == "sunny")
    #expect(inventory.unlocatedRanges.isEmpty)
}

@Test func joinedWordDoesNotSkipTheRemainingLine() {
    let inventory = WordAlignment.inventory(aligned("we have a picnic and suny weather."),
        hints: wordHints(["we", "havea", "picnic", "and", "sunny", "weather"]))
    #expect(inventory.locatedWords == 7)
    #expect(inventory.regions.count == 6)
    #expect(inventory.regions[1].original == "have a")
    #expect(inventory.regions[4].original == "suny")
    #expect(inventory.regions.last?.original == "weather")
    #expect(inventory.unlocatedRanges.isEmpty)
}

@Test func splitGeometryMapsToOneOriginalWithoutInsertingSpaces() {
    let inventory = WordAlignment.inventory(aligned("my grandparents helped."),
        hints: wordHints(["my", "grand", "parents", "helped"]))
    #expect(inventory.regions.count == 3)
    #expect(inventory.regions[1].original == "grandparents")
    #expect(inventory.regions[1].sourceWordCount == 2)
    #expect(inventory.locatedWords == 3)
}

@Test func aMissingWordBoxCannotConsumeAndDeleteAWholeSourceWord() {
    let transcript = aligned("i finish my homework.")
    let inventory = WordAlignment.inventory(transcript, hints: wordHints(["i", "finish", "homework"]))
    #expect(inventory.locatedWords == 3)
    #expect(inventory.regions.last?.original == "homework")
    #expect(!inventory.regions.contains { $0.original == "my homework" })
    #expect(inventory.unlocatedRanges.map { (transcript.text as NSString).substring(with: $0) } == ["my"])
    #expect(transcript.text == "i finish my homework.")
}

@Test func punctuationCannotBeSwallowedByAGroupedReplacement() {
    let text = "weekend, I go."
    let inventory = WordAlignment.inventory(aligned(text), hints: wordHints(["weekendI", "go"]))
    #expect(!inventory.regions.contains { $0.original?.contains(",") == true })
    #expect((text as NSString).substring(with: inventory.regions.last!.range!) == "go")
}

@Test func unalignedPageStillReadsEveryDetectedWordWithoutInventingAnchors() {
    let transcript = LineAlignment.fallback("I goed home.")
    let inventory = WordAlignment.inventory(transcript, hints: wordHints(["I", "go", "home"]))
    #expect(inventory.regions.count == 3)
    #expect(inventory.regions.allSatisfy { $0.range == nil })
    #expect(inventory.locatedWords == 0)
    #expect(!inventory.unlocatedRanges.isEmpty)
}

@Test func independentReadingCannotReplacePunctuationOrReturnAnExplanation() {
    #expect(WordAlignment.lexicalReading("weekend,") == "weekend")
    #expect(WordAlignment.lexicalReading("don't") == "don't")
    #expect(WordAlignment.lexicalReading("have a") == "have a")
    #expect(WordAlignment.lexicalReading("sunny\nweather") == nil)
    #expect(WordAlignment.lexicalReading("The word is: sunny") == nil)
}

@Test func independentLetterCountPreventsWholePageSpellingNormalization() {
    #expect(LiteralVerification.independentPreference(original: "sunny", isolated: "suny", hint: "suny",
        originalScore: 0.211, literalScore: 0.081) == "independent_letter_count")
    #expect(LiteralVerification.independentPreference(original: "weather", isolated: "wether", hint: "wether",
        originalScore: 0.084, literalScore: 0.123) == "independent_letter_count")
    #expect(LiteralVerification.independentPreference(original: "with", isolated: "with", hint: "wih",
        originalScore: 0.13, literalScore: 0.014) == nil)
}

@Test func twoIndependentReadingsCannotForceAnUnsupportedSubstitution() {
    #expect(LiteralVerification.independentPreference(original: "clean", isolated: "chean", hint: "chean",
        originalScore: 0.157, literalScore: 0.093) == nil)
    #expect(LiteralVerification.independentPreference(original: "clean", isolated: "chean", hint: "chean",
        originalScore: 0.038, literalScore: 0.044) == nil)
    #expect(LiteralVerification.independentPreference(original: "felted", isolated: "feeled", hint: "feeled",
        originalScore: 0.039, literalScore: 0.069) == "independent_visual_agreement")
}

@Test func unmatchedPrintedHeaderCannotBeMappedToAHandwrittenWord() {
    let text = "3. 题目说明。\nI'm a student."
    let transcript = LineAlignment.makeTranscript(text: text, hints: [
        TextHint(text: "Im is a student", rect: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.1))
    ])
    #expect(transcript.isAligned)
    #expect(!transcript.isFullyAligned)
    #expect(transcript.lines.count == 2)
    #expect(!transcript.lines[0].hasGeometry)
    #expect(transcript.lines[1].sourceRowID == 1)
    #expect(transcript.lines.map { transcript.text(in: $0) }.joined() == text)
    let inventory = WordAlignment.inventory(transcript, hints: wordHints(["Im", "is", "a", "student"]))
    #expect(!inventory.regions.contains { $0.original == "3" })
    #expect(inventory.regions.first?.original == "I'm")
    #expect(inventory.regions.first?.lineID == 2)
    #expect(inventory.regions.first { $0.hint == "is" }?.original == nil)
}
@Test func anAlternateImageDisagreementCannotBeHiddenByAJevChoice() throws {
    let transcript = LineAlignment.makeTranscript(text: "My freind came.", hints: [
        .init(text: "My freind came.", rect: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.04))
    ])
    let hints = [WordHint(lineID: 1, text: "freind", rect: .init(x: 0.25, y: 0.1, width: 0.2, height: 0.04), confidence: 1)]
    let region = try #require(WordAlignment.inventory(transcript, hints: hints).regions.first)
    var check = WordCheck(region: region, isolated: "freind", sourceReading: "friend", sourceChecked: true)
    check.selected = "freind"
    #expect(check.readingsDisagree)
    var stable = WordCheck(region: region, isolated: "freind", sourceReading: "freind", sourceChecked: true)
    stable.selected = "freind"
    #expect(!stable.readingsDisagree)
}

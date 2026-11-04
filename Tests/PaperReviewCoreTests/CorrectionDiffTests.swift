import Foundation
import Testing
@testable import PaperReviewCore

@Test func adjacentCorrectionsGetExactSeparateWordAnchors() throws {
    let source = LineAlignment.fallback("The wether is suny.")
    let edits = try CorrectionDiff.edits(source: source, corrected: "The weather was sunny.")
    #expect(edits.map(\.quote) == ["wether", "is", "suny"])
    #expect(edits.map(\.suggestion) == ["weather", "was", "sunny"])
    for edit in edits { #expect((source.text as NSString).substring(with: edit.range) == edit.quote) }
    #expect(source.text == "The wether is suny.")
}

@Test func duplicateWordsAndEmojiKeepTheirOriginalUTF16Positions() throws {
    let text = "👩🏽‍🏫 My freind likes my freind."
    let edits = try CorrectionDiff.edits(source: LineAlignment.fallback(text), corrected: "👩🏽‍🏫 My freind likes my friend.")
    #expect(edits.count == 1)
    #expect(edits[0].range == (text as NSString).range(of: "freind", options: .backwards))
}

@Test func contextualSweepsRetainUniqueSourceCandidatesWithStableIDs() throws {
    let source = LineAlignment.fallback("The wether is suny.")
    let a = try CorrectionDiff.edits(source: source, corrected: "The weather is sunny.")
    let b = try CorrectionDiff.edits(source: source, corrected: "The weather was sunny.")
    let merged = try CorrectionDiff.merge([a, b, a])
    #expect(merged.map(\.id) == [1, 2, 3])
    #expect(merged.map(\.quote) == ["wether", "is", "suny"])
    #expect(merged.map(\.suggestion) == ["weather", "was", "sunny"])
}

@Test func insertedWordsAndPunctuationBorrowOnlyTheirRealSourceAnchor() throws {
    for (source, target, quote, suggestion) in [
        ("I book.", "I read a book.", "book", "read a book"),
        ("I went home", "I went home.", "home", "home."),
        ("hello", "\"hello\"", "hello", "\"hello\"")
    ] {
        let edits = try CorrectionDiff.edits(source: LineAlignment.fallback(source), corrected: target)
        #expect(edits.count == 1 && edits[0].quote == quote && edits[0].suggestion == suggestion)
    }
}

@Test func deletedWordsAndJoinedWordsRemainSourceQuotations() throws {
    let repeated = "I really really like it."
    let deletion = try CorrectionDiff.edits(source: LineAlignment.fallback(repeated), corrected: "I really like it.")
    #expect(deletion.count == 1 && deletion[0].quote == "really" && deletion[0].suggestion.isEmpty)
    let joined = try CorrectionDiff.edits(source: LineAlignment.fallback("It is alot."), corrected: "It is a lot.")
    #expect(joined.count == 1 && joined[0].quote == "alot" && joined[0].suggestion == "a lot")
}

@Test func draftWhitespaceNeverReformatsTheSourceAndCrossLineChangesKeepTheirRanges() throws {
    let text = "I goed\n\nhome."
    let source = LineAlignment.fallback(text)
    let edits = try CorrectionDiff.edits(source: source, corrected: "I went home.")
    #expect(edits.count == 1 && edits[0].quote == "goed" && edits[0].suggestion == "went")
    #expect(try CorrectionDiff.edits(source: source, corrected: "I goed home.").isEmpty)
    #expect(source.text == text)
}

@Test @MainActor func localSpellingCluesAreReadOnlyAndDoNotTreatNamesOrUKVariantsAsUSCorrections() {
    let text = "A suny day was beautifull. My friend Suny lives in the city centre."
    let clues = EnglishSpellingClues.collect(text)
    #expect(clues.contains { $0.word == "suny" && $0.guesses.contains("sunny") })
    #expect(clues.contains { $0.word == "beautifull" && $0.guesses.contains("beautiful") })
    #expect(!clues.contains { $0.word == "Suny" || $0.word == "centre" })
    #expect(text == "A suny day was beautifull. My friend Suny lives in the city centre.")
}

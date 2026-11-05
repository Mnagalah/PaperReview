import Foundation
import Testing
import PaperReviewCore
@testable import PaperReviewLocalModels

@Test @MainActor func localSpellingCluesAreReadOnlyAndDoNotTreatNamesOrUKVariantsAsUSCorrections() {
    let text = "A suny day was beautifull. My friend Suny lives in the city centre."
    let clues = EnglishSpellingClues.collect(text)
    #expect(clues.contains { $0.word == "suny" && $0.guesses.contains("sunny") })
    #expect(clues.contains { $0.word == "beautifull" && $0.guesses.contains("beautiful") })
    #expect(!clues.contains { $0.word == "Suny" || $0.word == "centre" })
    #expect(text == "A suny day was beautifull. My friend Suny lives in the city centre.")
}

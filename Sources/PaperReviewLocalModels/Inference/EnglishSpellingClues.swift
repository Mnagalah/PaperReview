import AppKit
import Foundation
import PaperReviewCore

struct EnglishSpellingClue: Codable, Sendable {
    let word: String
    let guesses: [String]
}

/// The system lexicon supplies untrusted recall clues only. It never writes
/// corrections, runs grammar checking, learns words, or changes user settings.
enum EnglishSpellingClues {
    @MainActor static func collect(_ text: String) -> [EnglishSpellingClue] {
        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        let ns = text as NSString
        var clues: [EnglishSpellingClue] = [], seen: Set<String> = [], cursor = 0
        while cursor < ns.length {
            let range = checker.checkSpelling(of: text, startingAt: cursor, language: "en_US", wrap: false,
                inSpellDocumentWithTag: tag, wordCount: nil)
            guard range.location != NSNotFound, range.length > 0 else { break }
            cursor = NSMaxRange(range)
            let word = ns.substring(with: range)
            // Unknown names and valid UK variants must not be pushed toward
            // a US dictionary spelling. MiniCPM still reads the entire essay.
            guard word.first?.isLowercase == true, !seen.contains(word) else { continue }
            if checker.availableLanguages.contains("en_GB"),
               checker.checkSpelling(of: word, startingAt: 0, language: "en_GB", wrap: false,
                inSpellDocumentWithTag: tag, wordCount: nil).location == NSNotFound { continue }
            let guesses = Array((checker.guesses(forWordRange: range, in: text, language: "en_US", inSpellDocumentWithTag: tag) ?? []).prefix(3))
            guard !guesses.isEmpty else { continue }
            seen.insert(word); clues.append(EnglishSpellingClue(word: word, guesses: guesses))
        }
        return clues
    }
}

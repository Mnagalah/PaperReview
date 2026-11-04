import Foundation

struct EnglishUsageFocus: Sendable {
    let draft: CorrectionDraft
    let sentence: String
    let options: [String]
    var explanation: String {
        draft.quote.lowercased() == "accept" ? "这里表示排除，应使用 except。" : "持续的时间长度应使用 for。"
    }

    static func collect(_ transcript: Transcript) -> [EnglishUsageFocus] {
        // Whitespace normalization preserves UTF16 offsets and joins physical
        // handwriting rows before finding sentences. The source is unchanged.
        let text = transcript.text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let ns = text as NSString
        var sentences: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { _, range, _, _ in
            sentences.append(NSRange(range, in: text))
        }
        let words = try! NSRegularExpression(pattern: #"(?i)(?<![\p{L}\p{N}'’])(?:accept|since)(?![\p{L}\p{N}'’])"#)
        return words.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let range = match.range
            guard let sentenceRange = sentences.first(where: { NSIntersectionRange($0, range) == range }),
                  let line = transcript.lines.first(where: { NSLocationInRange(range.location, $0.range) }) else { return nil }
            let word = ns.substring(with: range)
            let before = ns.substring(with: NSRange(location: sentenceRange.location, length: range.location - sentenceRange.location))
            // A title-cased word inside a sentence may be a name; a directly
            // quoted word is literal text rather than a usage correction.
            if word == word.capitalized, !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            let after = ns.substring(with: NSRange(location: NSMaxRange(range), length: NSMaxRange(sentenceRange) - NSMaxRange(range)))
            if let left = before.last, let right = after.first,
               ["\"", "'", "“", "‘"].contains(String(left)), ["\"", "'", "”", "’"].contains(String(right)) { return nil }
            if word.lowercased() == "since", !startsWithDuration(after) { return nil }
            let options = word.lowercased() == "accept" ? ["accept", "except"] : ["for", "since"]
            let replacement = word.lowercased() == "accept" ? "except" : "for"
            let suggestion = matchingCase(replacement, source: word)
            let local = NSRange(location: range.location - sentenceRange.location, length: range.length)
            let sentence = (ns.substring(with: sentenceRange) as NSString).replacingCharacters(in: local, with: "[BLANK]")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return EnglishUsageFocus(draft: CorrectionDraft(id: 0, lineID: line.id, start: range.location, length: range.length,
                quote: word, suggestion: suggestion), sentence: sentence, options: options)
        }
    }

    private static func startsWithDuration(_ text: String) -> Bool {
        let pattern = #"(?i)^\s+(?:(.*?)\s+)?(seconds?|minutes?|hours?|days?|weeks?|months?|years?|decades?|centuries|time)\b"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return false }
        let remainder = ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if remainder.range(of: #"^(?:ago|earlier|before)\b"#, options: .regularExpression) != nil { return false }
        var quantity = match.range(at: 1).location == NSNotFound ? "" : ns.substring(with: match.range(at: 1)).lowercased()
        quantity = quantity.replacingOccurrences(of: #"^(?:the\s+)?(?:last|past)\s+"#, with: "", options: .regularExpression)
        if quantity.isEmpty { return ns.substring(with: match.range(at: 2)).lowercased().hasSuffix("s") }
        if ["a", "an", "a few", "a couple of", "several", "many", "few", "some", "a long", "a short"].contains(quantity) { return true }
        if Double(quantity) != nil { return true }
        let number = NumberFormatter(); number.locale = Locale(identifier: "en_US"); number.numberStyle = .spellOut
        return number.number(from: quantity) != nil
    }

    static func matchingCase(_ word: String, source: String) -> String {
        if source == source.uppercased() { return word.uppercased() }
        return source == source.capitalized ? word.capitalized : word
    }
}

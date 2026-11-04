import Foundation
import Testing
@testable import PaperReviewCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_REAL_MODELS"] == "1"))
func semanticReviewUnderstandsContext() async throws {
    let text = """
    The box of old books are heavy.
    Everyone was there accept Tom.
    Please accept my apology.
    I have lived here since three years.
    I visited Paris last year. I live in London now.
    If I were you, I would wait.
    I do not like tea.
    It was beautifull.
    """
    let transcript = LineAlignment.fallback(text)
    let start = Date()
    let result = try await ModelClient().review(transcript: transcript, base: "http://127.0.0.1:18501")
    struct Evidence: Encodable {
        let input: String
        let seconds: Double
        let issues: [ReviewIssue]
        let rejectedCount: Int
        let modelEvidence: ReviewModelEvidence?
    }
    let evidence = Evidence(input: text, seconds: Date().timeIntervalSince(start), issues: result.issues, rejectedCount: result.rejectedCount, modelEvidence: result.modelEvidence)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let output = ProcessInfo.processInfo.environment["PAPERREVIEW_SEMANTIC_EVIDENCE"]
        .map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("docs/verification/semantic-8case-result.json")
    try encoder.encode(evidence).write(to: output, options: .atomic)
    #expect(transcript.text == text)
    for (line, quote, suggestion) in [(1,"are","is"), (2,"accept","except"), (4,"since","for"), (8,"beautifull","beautiful")] {
        #expect(result.issues.contains { $0.lineID == line && $0.quote == quote && $0.suggestion == suggestion })
    }
    #expect(result.issues.allSatisfy { [1,2,4,8].contains($0.lineID) })
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_NORMAL_REVIEW_RECORD"] != nil))
func normalNarrativeReviewRecoversSpellingAndInheritedPastTimeWithoutChangingFacts() async throws {
    struct Stored: Decodable { let transcript: Transcript }
    let path = try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_NORMAL_REVIEW_RECORD"])
    let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let cases: [(String, Transcript, [(String, String)])] = [
        ("handwriting", stored.transcript, [("have", "had"), ("go", "went"), ("wether", "weather"), ("is", "was"),
            ("suny", "sunny"), ("i", "I"), ("finish", "finished"), ("visit", "visited"), ("help", "helped"), ("they", "them"), ("feeled", "felt")]),
        ("unseen-narrative", LineAlignment.fallback("Yesterday, we walk to a museum.\nThe hall is quiet.\nMy sister buy a ticket and take many photos.\nWe return home after lunch.\nIt was a beautifull trip."),
            [("walk", "walked"), ("is", "was"), ("buy", "bought"), ("take", "took"), ("return", "returned"), ("beautifull", "beautiful")]),
        ("valid-time-shifts", LineAlignment.fallback("Last weekend, I visited my aunt. I live near her now. She has a sunny garden. I usually go there on Saturdays. If I were taller, I could reach the shelf. My friend Suny lives in the city centre. Tomorrow, I will visit her. I do not like tea."), [])
    ]
    struct Evidence: Encodable {
        let name: String
        let input: String
        let seconds: Double
        let issues: [ReviewIssue]
        let modelEvidence: ReviewModelEvidence?
        let missing: [String]
    }
    let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_NORMAL_REVIEW_EVIDENCE"]))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var evidence: [Evidence] = []
    for (name, transcript, expected) in cases {
        let start = Date()
        let result = try await ModelClient().review(transcript: transcript, base: "http://127.0.0.1:18501")
        let missing = expected.filter { quote, suggestion in
            !result.issues.contains { $0.quote == quote && $0.suggestion == suggestion }
        }.map { $0.0 + " → " + $0.1 }
        evidence.append(Evidence(name: name, input: transcript.text, seconds: Date().timeIntervalSince(start),
            issues: result.issues, modelEvidence: result.modelEvidence, missing: missing))
        try encoder.encode(evidence).write(to: output, options: .atomic)
        #expect(missing.isEmpty)
        if expected.isEmpty { #expect(result.issues.isEmpty) }
        for issue in result.issues {
            #expect((transcript.text as NSString).substring(with: issue.range) == issue.quote)
            #expect(issue.revision == transcript.revision)
        }
        if name == "handwriting" {
            #expect(transcript == stored.transcript)
            #expect(result.issues.filter { $0.quote == "have" && $0.suggestion == "had" }.count == 2)
        }
    }
}

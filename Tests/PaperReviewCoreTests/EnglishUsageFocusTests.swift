import Foundation
import Testing
@testable import PaperReviewCore

@Test func usageFocusKeepsSourceRangesAndJoinsPhotographedRowsWithinASentence() throws {
    let source = LineAlignment.fallback("👩🏽‍🏫 Everyone was there accept Tom. Please accept my apology.\nI have lived here since\nthree years.")
    let focuses = EnglishUsageFocus.collect(source)
    #expect(focuses.count == 3)
    #expect(focuses.map(\.draft.quote) == ["accept", "accept", "since"])
    #expect(focuses[0].sentence == "👩🏽‍🏫 Everyone was there [BLANK] Tom.")
    #expect(focuses[1].sentence == "Please [BLANK] my apology.")
    #expect(focuses[2].sentence == "I have lived here [BLANK] three years.")
    for focus in focuses { #expect((source.text as NSString).substring(with: focus.draft.range) == focus.draft.quote) }
    #expect(focuses[0].draft.start != focuses[1].draft.start)
    #expect(source.text.contains("since\nthree"))
}

@Test func usageCandidatesDistinguishDurationsFromDatesEventsAndCauses() {
    for sentence in ["She has worked here since six months.", "We have waited since fifteen minutes.",
                     "I have lived here since the last five months.", "They have been here since a few weeks.",
                     "I have waited since an hour.", "It has been quiet since years."] {
        #expect(EnglishUsageFocus.collect(LineAlignment.fallback(sentence)).count == 1)
    }
    for sentence in ["I have lived here since 2020.", "She has worked here since last May.",
                     "I have known him since I was ten.", "I have known him since I was three years old.",
                     "We have lived here since three years ago.", "Since three years ago, we have lived here.",
                     "We have lived here since a few weeks ago, and we like it.",
                     "I have lived here since one week before the wedding.",
                     "Since it was raining, we stayed inside."] {
        #expect(EnglishUsageFocus.collect(LineAlignment.fallback(sentence)).isEmpty)
    }
}

@Test func usageFocusDoesNotMatchInsideWordsLiteralWordQuotesOrNames() {
    let text = "The acceptable acceptance was accepted. Mr Accept is here. My friend Since lives nearby. The word ‘accept’ has six letters. Everyone except Tom was there. I have lived here for three years."
    #expect(EnglishUsageFocus.collect(LineAlignment.fallback(text)).isEmpty)
    let source = LineAlignment.fallback("ACCEPT my apology. Since three years, I have lived here.")
    let focuses = EnglishUsageFocus.collect(source)
    #expect(focuses.map(\.draft.suggestion) == ["EXCEPT", "For"])
}

private func usageResponse(_ content: String, finish: String = "stop") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content], "finish_reason": finish]]])
}

@Test func usageChoiceUsesTheFixedModelAndRejectsInvalidOrTruncatedAnswers() throws {
    let focus = try #require(EnglishUsageFocus.collect(LineAlignment.fallback("Everyone was there accept Tom.")).first)
    let request = ModelClient.usageRequest(focus)
    #expect(request["model"] as? String == "MiniCPM5-2B")
    #expect(request["max_tokens"] as? Int == 128)
    #expect((request["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"] == false)
    let input = try #require((request["messages"] as? [[String: String]])?.last?["content"])
    let payload = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
    #expect(payload["sentence"] as? String == "Everyone was there [BLANK] Tom.")
    #expect(payload["current_word"] == nil && payload["reference_answer"] == nil)
    #expect(try ModelClient.usageChoice(usageResponse(#"{"word":"except"}"#), focus: focus) == "except")
    #expect(throws: ModelError.self) { try ModelClient.usageChoice(usageResponse(#"{"word":"expect"}"#), focus: focus) }
    #expect(throws: ModelError.self) { try ModelClient.usageChoice(usageResponse(#"{"word":"except"}"#, finish: "length"), focus: focus) }
}

@Test func focusedUsageDecisionsMergeWithoutLosingGeneralCorrectionsOrDuplicateWordPositions() throws {
    let source = LineAlignment.fallback("The box of books are heavy. Everyone was there accept Tom. Please accept my apology. I have lived here since three years.")
    let focuses = EnglishUsageFocus.collect(source)
    let drafts = try CorrectionDiff.edits(source: source, corrected: "The box of books is heavy. Everyone was there except Tom. Please except my apology. I have lived here since three years.")
    let decisions = drafts.map { ReviewDraftDecision(id: $0.id, accept: true, kind: .grammar, explanation: "测试。") }
    let usage = zip(focuses, ["except", "accept", "for"]).map { ($0.0, $0.1) }
    let merged = try ModelClient.mergeUsage(drafts: drafts, decisions: decisions, usage: usage)
    #expect(merged.drafts.map(\.id) == Array(1...merged.drafts.count))
    #expect(merged.decisions.map(\.accept) == [true, true, false, true])
    #expect(merged.drafts.map(\.quote) == ["are", "accept", "accept", "since"])
    for draft in merged.drafts { #expect((source.text as NSString).substring(with: draft.range) == draft.quote) }
}

@Test func usageWorkingCopyNeverChangesTheSourceOrItsGeometryAndKeepsLaterOffsetsValid() throws {
    let transcript = LineAlignment.fallback("👩🏽‍🏫 I have lived here since\nthree years. Everyone was there accept Tom. Please accept my apology.")
    let focuses = EnglishUsageFocus.collect(transcript)
    let usage = zip(focuses, ["for", "except", "accept"]).map { ($0.0, $0.1) }
    let copy = ModelClient.usageWorkingText(transcript, usage: usage)
    #expect(copy == "👩🏽‍🏫 I have lived here for\nthree years. Everyone was there except Tom. Please accept my apology.")
    #expect(transcript.text.contains("since\nthree"))
    #expect(transcript.text.contains("there accept Tom"))
    let defaults = try ModelClient.draftRequest(transcript)
    #expect((defaults["messages"] as? [[String: String]])?.last?["content"] == transcript.text)
    let request = try ModelClient.draftRequest(transcript, workingText: copy)
    #expect((request["messages"] as? [[String: String]])?.last?["content"] == copy)
}

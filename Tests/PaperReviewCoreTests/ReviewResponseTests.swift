import Foundation
import Testing
@testable import PaperReviewCore

@Test func semanticDraftAndVerificationReadOnlyTheOriginalAndDoNotAskTheModelForPositions() throws {
    let text = "My freind go home.\nI have lived here since three years."
    let transcript = LineAlignment.fallback(text)
    let drafts = try CorrectionDiff.edits(source: transcript, corrected: "My friend goes home.\nI have lived here for three years.")
    let request = try ModelClient.reviewRequest(transcript, drafts: drafts)
    let maximum = try #require(request["max_tokens"] as? Int)
    #expect(maximum >= 2048)
    #expect((request["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"] == false)
    let messages = try #require(request["messages"] as? [[String: String]])
    #expect(messages.map { $0["role"] } == ["system", "user"])
    let input = try #require(messages.last?["content"])
    let payload = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
    #expect(payload["original"] as? String == text)
    #expect(payload["candidates"] != nil && payload["corrected_essay"] == nil)
    #expect(!input.contains("She go home."))
    #expect(!input.contains("image_url"))
    #expect(request["model"] as? String == "MiniCPM5-2B")
    #expect(request["temperature"] as? Double == 0.2 && request["min_p"] as? Double == 0.0)
    let preliminary = try ModelClient.draftRequest(transcript)
    #expect((preliminary["messages"] as? [[String: String]])?.last?["content"] == text)
    #expect(transcript.text == text)
}

private func response(_ content: String?, finish: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["choices": [[
        "message": ["content": content.map { $0 as Any } ?? NSNull()], "finish_reason": finish
    ]]])
}

@Test func truncatedReviewIsNeverSalvagedIntoAnEmptyOrCompletedPass() throws {
    let transcript = LineAlignment.fallback("I goed home.")
    for text in [nil, "", "{\"issues\":[]}"] as [String?] {
        do {
            _ = try ModelClient.decodeReviewResponse(response(text, finish: "length"), transcript: transcript)
            Issue.record("A truncated response must not complete the review.")
        } catch {
            #expect(error.localizedDescription.contains("截断"))
        }
    }
}

@Test func completedReviewStillRequiresJSONAndExactSourceQuotes() throws {
    let transcript = LineAlignment.fallback("I goed home.")
    let json = """
    {"issues":[{"line":1,"quote":"goed","occurrence":1,"kind":"grammar","suggestion":"went","explanation":"go的过去式是went。"}]}
    """
    let result = try ModelClient.decodeReviewResponse(response(json, finish: "stop"), transcript: transcript)
    #expect(result.issues.count == 1 && result.issues[0].quote == "goed")
    #expect(transcript.text == "I goed home.")
    #expect(throws: ModelError.self) {
        try ModelClient.decodeReviewResponse(response("Everything looks good.", finish: "stop"), transcript: transcript)
    }
    #expect(throws: ModelError.self) {
        try ModelClient.decodeReviewResponse(response(nil, finish: "stop"), transcript: transcript)
    }
}

@Test func everyDraftNeedsAnExplicitDecisionAndAcceptedReasonsMustBeChinese() throws {
    let transcript = LineAlignment.fallback("The wether is suny.")
    let drafts = try CorrectionDiff.edits(source: transcript, corrected: "The weather is sunny.")
    let valid = #"{"issues":[{"id":1,"accept":true,"kind":"spelling","explanation":"weather拼写缺少字母a。"},{"id":2,"accept":false,"kind":"spelling","explanation":"保留供核实。"}]}"#
    let result = try ModelClient.decodeDraftDecisions(response(valid, finish: "stop"), transcript: transcript, drafts: drafts)
    #expect(result.issues.count == 1 && result.issues[0].quote == "wether")
    #expect(result.modelEvidence?.decisions.count == 2)
    #expect(transcript.text == "The wether is suny.")
    for invalid in [#"{"issues":[]}"#,
        #"{"issues":[{"id":1,"accept":true,"kind":"spelling","explanation":"English only"},{"id":2,"accept":true,"kind":"spelling","explanation":"拼写。"}]}"#,
        #"{"issues":[{"id":1,"accept":true,"kind":"spelling","explanation":"拼写。"},{"id":1,"accept":true,"kind":"spelling","explanation":"拼写。"}]}"#] {
        #expect(throws: ModelError.self) { try ModelClient.decodeDraftDecisions(response(invalid, finish: "stop"), transcript: transcript, drafts: drafts) }
    }
    #expect(throws: ModelError.self) {
        try ModelClient.decodeDraftDecisions(response(valid, finish: "length"), transcript: transcript, drafts: drafts)
    }
}

@Test func preliminaryTruncationIsNotACompletedPassAndOnlyItsLayoutIsNormalized() throws {
    let transcript = LineAlignment.fallback("I goed\nhome.")
    let json = #"{"corrected_text":"I went\\nhome."}"#
    let drafts = try ModelClient.decodeDraftResponse(response(json, finish: "stop"), transcript: transcript)
    #expect(drafts.count == 1 && drafts[0].quote == "goed" && drafts[0].suggestion == "went")
    #expect(transcript.text == "I goed\nhome.")
    #expect(throws: ModelError.self) { try ModelClient.decodeDraftResponse(response(json, finish: "length"), transcript: transcript) }
}

@Test func reasonTranslationCannotChangeVerdictsOrCorrectionsAndCannotDropIDs() throws {
    let decisions = [ReviewDraftDecision(id: 1, accept: true, kind: .grammar, explanation: "The event happened last weekend."),
                     ReviewDraftDecision(id: 2, accept: false, kind: .spelling, explanation: "It is a proper name.")]
    let json = #"{"explanations":[{"id":1,"explanation":"事件发生在上周末，应使用过去时。","accept":false}]}"#
    let localized = try ModelClient.localizedDecisions(response(json, finish: "stop"), decisions: decisions)
    #expect(localized[0].accept && localized[0].kind == .grammar)
    #expect(localized[0].explanation == "事件发生在上周末，应使用过去时。")
    #expect(!localized[1].accept && localized[1].explanation == decisions[1].explanation)
    #expect(throws: ModelError.self) { try ModelClient.localizedDecisions(response(#"{"explanations":[]}"#, finish: "stop"), decisions: decisions) }
}

@Test func contextualSweepUsesTheFixedModelAndABoundedThinkingBudget() throws {
    for thinking in [false, true] {
        let text = "Yesterday, I walk home."
        let request = ModelClient.grammarRequest(text, thinking: thinking)
        #expect(request["model"] as? String == "MiniCPM5-2B")
        #expect((request["messages"] as? [[String: String]])?.last?["content"] == text)
        #expect((request["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"] == thinking)
        #expect(request["reasoning_budget_tokens"] as? Int == (thinking ? 512 : nil))
    }
}

@Test func conflictingAcceptedCandidatesDoNotOverwriteAValidReview() throws {
    let transcript = LineAlignment.fallback("My freind came.")
    let drafts = try CorrectionDiff.merge([
        CorrectionDiff.edits(source: transcript, corrected: "My friend came."),
        CorrectionDiff.edits(source: transcript, corrected: "My friends came.")])
    let conflicting = #"{"issues":[{"id":1,"accept":true,"kind":"spelling","explanation":"拼写。"},{"id":2,"accept":true,"kind":"spelling","explanation":"拼写。"}]}"#
    #expect(throws: ModelError.self) { try ModelClient.decodeDraftDecisions(response(conflicting, finish: "stop"), transcript: transcript, drafts: drafts) }
}

@Test func semanticActionsHaveExplicitDirectionAndLocalizedCategories() throws {
    let transcript = LineAlignment.fallback("Yesterday we walk in the suny park.")
    let drafts = try CorrectionDiff.edits(source: transcript, corrected: "Yesterday we walked in the sunny park.")
    let request = try ModelClient.actionRequest(transcript, drafts: drafts)
    #expect(request["model"] as? String == "MiniCPM5-2B")
    #expect(request["reasoning_budget_tokens"] as? Int == 512)
    #expect((request["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"] == true)
    let messages = try #require(request["messages"] as? [[String: String]])
    let input = try #require(messages.last?["content"])
    let payload = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
    #expect(payload["original"] as? String == transcript.text)
    #expect(!String(describing: payload).contains("image_url"))
    let json = #"{"issues":[{"id":1,"action":"apply","category":"tense"},{"id":2,"action":"keep_original","category":"not_an_error"}]}"#
    let decisions = try ModelClient.actionDecisions(response(json, finish: "stop"), drafts: drafts)
    #expect(decisions[0].accept && decisions[0].kind == .grammar && decisions[0].basis == "tense")
    #expect(decisions[0].explanation.contains("时间背景"))
    #expect(!decisions[1].accept)
    for invalid in [#"{"issues":[]}"#,
                    #"{"issues":[{"id":1,"action":"apply","category":"not_an_error"},{"id":2,"action":"keep_original","category":"spelling"}]}"#,
                    #"{"issues":[{"id":1,"action":"apply","category":"tense"},{"id":1,"action":"apply","category":"spelling"}]}"#] {
        #expect(throws: ModelError.self) { try ModelClient.actionDecisions(response(invalid, finish: "stop"), drafts: drafts) }
    }
    #expect(throws: ModelError.self) { try ModelClient.actionDecisions(response(json, finish: "length"), drafts: drafts) }
    let legacy = #"{"id":1,"accept":true,"kind":"grammar","explanation":"原有理由"}"#
    #expect(try JSONDecoder().decode(ReviewDraftDecision.self, from: Data(legacy.utf8)).basis == nil)
}

import Foundation
import Testing
import PaperReviewCore
@testable import PaperReview

@Test @MainActor func injectedModelReviewPreservesSourceAndKeepsLastValidAnnotationsOnFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-contract-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AssignmentRepository(root: root)
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = project.appendingPathComponent("docs/fixtures/synthetic-essay-tight-crop.png")
    var record = try await repository.importPhoto(source)
    let page = try await PhotoProcessor().prepare(Data(contentsOf: source))
    let transcript = LineAlignment.fallback("Yesterday, I walk in the suny park.")
    record.transcript = transcript; record.humanConfirmed = true; record.phase = .complete
    record.structureVersion = page.scan.version + ":" + PageScaffolding.version
    try await repository.savePage(page, id: record.id)
    try await repository.save(record)
    let module = ReviewFixtureModule(transcript: transcript)
    let workspace = WorkspaceStore(models: module, dataRoot: root)
    await workspace.restore()
    let job = try #require(workspace.selected)
    workspace.retry(job)
    try await waitUntilIdle(workspace)
    #expect(job.record.phase == .complete && job.record.transcript == transcript)
    #expect(job.record.issues.count == 1 && job.record.issues[0].quote == "suny")
    let previous = job.record.issues
    module.fails = true
    workspace.retry(job)
    try await waitUntilIdle(workspace)
    #expect(job.record.phase == .failed && job.record.failedPhase == .reviewing)
    #expect(job.record.issues == previous && job.record.transcript == transcript)
    #expect(module.sessions == 2)
    let saved = try #require(await repository.load().first)
    #expect(saved.issues == previous && saved.transcript == transcript)
}

@MainActor private func waitUntilIdle(_ workspace: WorkspaceStore) async throws {
    let deadline = ContinuousClock.now + .seconds(20)
    while workspace.activeID != nil && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(workspace.activeID == nil)
}

@MainActor private final class ReviewFixtureModule: ModelModule {
    let transcript: Transcript
    var fails = false
    var sessions = 0
    let readiness = ModelReadiness(required: [.ocr, .jev, .review], available: [.ocr, .jev, .review])
    let policy = RecognitionPolicy(threshold: 0.5, maximumAttempts: 3)
    let needsTerminationPreparation = false
    init(transcript: Transcript) { self.transcript = transcript }
    func makeSession() throws -> any ModelSession {
        sessions += 1
        return ReviewFixtureSession(expected: transcript, fails: fails, policy: policy)
    }
    func checkReadiness() async {}
    func prepareForTermination() async {}
}

private struct ReviewFixtureSession: ModelSession {
    let expected: Transcript
    let fails: Bool
    let policy: RecognitionPolicy
    let recognitionIdentity = "test-ocr"
    let verificationIdentity = "test-jev"
    func recognize(image: Data) async throws -> OCRResponse {
        Issue.record("Review-only retry must not call OCR")
        throw ModelError.emptyOCR
    }
    func score(original: Data, rendered: Data, text: String) async throws -> Double {
        Issue.record("Review-only retry must not call Jev")
        throw ModelError.invalidResponse("unexpected Jev call")
    }
    func review(transcript: Transcript) async throws -> ReviewResult {
        #expect(transcript == expected)
        if fails { throw ModelError.unavailable("测试审核服务") }
        return IssueAnchoring.anchor([.init(line: 1, quote: "suny", occurrence: 1, kind: .spelling,
            suggestion: "sunny", explanation: "单词缺少字母 n。")], to: transcript)
    }
}

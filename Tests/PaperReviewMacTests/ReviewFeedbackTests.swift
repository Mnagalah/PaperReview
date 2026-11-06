import AppKit
import SwiftUI
import Testing
import PaperReviewCore
@testable import PaperReview

@Test @MainActor func reviewFeedbackRiskSuggestionsCanBeConfirmedDiscardedRestoredAndExported() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-risk-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(models: FeedbackQueueModule(), dataRoot: root)
    let transcript = LineAlignment.fallback("I speak English. I have a book.")
    let issues = IssueAnchoring.anchor([
        .init(line: 1, quote: "speak", occurrence: 1, kind: .grammar, suggestion: "speaking", explanation: "示例建议"),
        .init(line: 1, quote: "have", occurrence: 1, kind: .grammar, suggestion: "", explanation: "示例删除")
    ], to: transcript).issues
    var record = AssignmentRecord(title: "风险建议", originalFilename: "fixture.png")
    record.transcript = transcript; record.phase = .complete; record.deferredReviewIssues = issues
    let job = Assignment(record: try JSONDecoder().decode(AssignmentRecord.self, from: JSONEncoder().encode(record)))
    store.assignments = [job]; store.selectedID = job.id
    #expect(job.record.issues.isEmpty && job.record.pendingIssues.count == 2)
    #expect(job.record.pendingIssues.allSatisfy(job.record.needsRecognitionCheck))
    let pendingExport = MarkdownExport.annotated(transcript, issues: job.record.reviewIssues, humanConfirmed: false,
        teacherReview: job.record.review, uncertainIssueIDs: job.record.recognitionWarningIDs)
    #expect(pendingExport.contains("可能识别有误") && pendingExport.contains("speaking"))
    let undo = UndoManager(); undo.groupsByEvent = false
    undo.beginUndoGrouping(); store.resolve(job, issue: issues[0], as: .annotation, undoManager: undo); undo.endUndoGrouping()
    await store.finishReviewWrites()
    #expect(job.record.pendingIssues.count == 1 && job.record.review.confirmed.count == 1)
    undo.undo(); await store.finishReviewWrites()
    #expect(job.record.pendingIssues.count == 2)
    undo.redo(); await store.finishReviewWrites()
    store.resolve(job, issue: issues[1], as: .keepOriginal); await store.finishReviewWrites()
    let decision = try #require(job.record.review.discarded.first)
    store.restoreSuggestion(decision, job: job, undoManager: nil); await store.finishReviewWrites()
    #expect(job.record.pendingIssues.map(\.id) == [issues[1].id])
    store.completeReview(job, keepRemaining: true, undoManager: nil); await store.finishReviewWrites()
    #expect(job.isReviewed && job.record.pendingIssues.isEmpty)
    let saved = try #require(await store.repository.load().first)
    #expect(saved.transcript == transcript && saved.deferredReviewIssues == issues)
    #expect(saved.review.confirmed.count == 1 && saved.review.discarded.count == 1)
    let exported = MarkdownExport.annotated(transcript, issues: saved.reviewIssues, humanConfirmed: false, teacherReview: saved.review)
    #expect(exported.hasPrefix(transcript.text) && exported.contains("speaking"))
}

@Test func reviewFeedbackIgnoresStaleRiskAnchorsAndDeduplicatesCurrentSuggestions() {
    let transcript = LineAlignment.fallback("I speak English.")
    let issue = IssueAnchoring.anchor([.init(line: 1, quote: "speak", occurrence: 1, kind: .grammar,
        suggestion: "speaking", explanation: "示例")], to: transcript).issues[0]
    var record = AssignmentRecord(title: "fixture", originalFilename: "fixture.png")
    record.transcript = transcript; record.issues = [issue]; record.deferredReviewIssues = [issue, issue]
    #expect(record.reviewIssues.count == 1)
    record.issues = []; record.transcript = LineAlignment.fallback("I spoke English.")
    #expect(record.reviewIssues.isEmpty)
}

@Test @MainActor func reviewFeedbackFreshModelResultsRemainVisibleWhenPhotoAlignmentIsMissing() async throws {
    let module = FeedbackQueueModule()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-risk-pipeline-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, jobs) = try await feedbackWorkspace(root: root, module: module, count: 1)
    let job = jobs[0]; job.record.humanConfirmed = false
    let original = job.record.transcript
    store.retry(job)
    try await feedbackWait { job.record.phase == .reviewing }
    await module.gate.release()
    try await feedbackWait { store.activeID == nil }
    #expect(job.record.phase == .complete && job.record.issues.isEmpty)
    #expect(job.record.deferredReviewIssues?.count == 1 && job.record.pendingIssues.count == 1)
    #expect(job.record.needsRecognitionCheck(job.record.pendingIssues[0]))
    #expect(job.record.transcript == original)
    let saved = try #require(await store.repository.load().first)
    #expect(saved.pendingIssues.count == 1)
}

@Test(arguments: [false, true]) @MainActor
func reviewFeedbackQueuedRetryAndFailureShareBusyStateWithOrWithoutOldResults(hasOldResults: Bool) async throws {
    let module = FeedbackQueueModule()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-queue-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, jobs) = try await feedbackWorkspace(root: root, module: module, count: 2)
    let first = jobs[0], second = jobs[1]
    second.record.phase = .failed; second.record.failedPhase = .reviewing; second.record.error = "模拟审核失败"
    if !hasOldResults { second.record.issues = [] }
    let prior = second.record.reviewIssues
    store.retry(first)
    try await feedbackWait { first.record.phase == .reviewing }
    store.retry(second)
    #expect(second.record.phase == .queued && store.activeID == first.id)
    #expect(ReviewActivity(record: second.record)?.title == "等待队列中")
    #expect(ReviewActivity(record: second.record)?.isBusy == true)
    #expect(second.record.reviewIssues == prior && second.record.error == nil)
    store.retry(second) // Already enqueued: do not create another model session.
    #expect(module.sessions == 1)
    if let issue = prior.first {
        store.resolve(second, issue: issue, as: .annotation)
        #expect(second.record.review.decisions.isEmpty)
    }
    await module.gate.release()
    try await feedbackWait { store.activeID == second.id && second.record.phase == .reviewing }
    #expect(ReviewActivity(record: second.record)?.isBusy == true)
    #expect(ReviewActivity(record: second.record)?.title == "正在检查基础错误")
    await module.gate.release(fail: true)
    try await feedbackWait { store.activeID == nil }
    #expect(second.record.phase == .failed && second.record.reviewIssues == prior)
    #expect(ReviewActivity(record: second.record)?.canRetry == true)
    store.retry(second)
    #expect(ReviewActivity(record: second.record)?.isBusy == true)
    try await feedbackWait { second.record.phase == .reviewing }
    await module.gate.release()
    try await feedbackWait { store.activeID == nil }
    #expect(second.record.phase == .complete && ReviewActivity(record: second.record) == nil)
    #expect(module.sessions == 3 && second.record.pendingIssues.count == 1)
}

@MainActor private func feedbackWait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(15)
    while !predicate() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(predicate())
}

@MainActor private func feedbackWorkspace(root: URL, module: FeedbackQueueModule, count: Int) async throws -> (WorkspaceStore, [Assignment]) {
    let store = WorkspaceStore(models: module, dataRoot: root)
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = project.appendingPathComponent("docs/fixtures/synthetic-essay-tight-crop.png")
    let page = try await PhotoProcessor().prepare(Data(contentsOf: source))
    var jobs: [Assignment] = []
    for index in 0..<count {
        var record = AssignmentRecord(title: "队列测试 \(index)", originalFilename: "fixture.png")
        record.transcript = LineAlignment.fallback("I speak English."); record.humanConfirmed = true; record.phase = .complete
        record.structureVersion = page.scan.version + ":" + PageScaffolding.version
        record.issues = FeedbackQueueSession.result(record.transcript!).issues
        let job = Assignment(record: record); job.setPage(page)
        try await store.repository.save(job.record)
        try await store.repository.savePage(page, id: job.id)
        jobs.append(job)
    }
    store.assignments = jobs; store.selectedID = jobs.last?.id
    return (store, jobs)
}

private actor FeedbackReviewGate {
    var permits: [Bool] = []
    func release(fail: Bool = false) { permits.append(fail) }
    func wait() async throws {
        while permits.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        if permits.removeFirst() { throw ModelError.unavailable("模拟审核服务") }
    }
}

@MainActor private final class FeedbackQueueModule: ModelModule {
    let gate = FeedbackReviewGate()
    var sessions = 0
    let readiness = ModelReadiness(required: [])
    let policy = RecognitionPolicy(threshold: 0.5, maximumAttempts: 3)
    let needsTerminationPreparation = false
    func makeSession() throws -> any ModelSession { sessions += 1; return FeedbackQueueSession(gate: gate) }
    func checkReadiness() async {}
    func prepareForTermination() async {}
}

private struct FeedbackQueueSession: ModelSession {
    let gate: FeedbackReviewGate
    let policy = RecognitionPolicy(threshold: 0.5, maximumAttempts: 3)
    let recognitionIdentity = "fixture-ocr", verificationIdentity = "fixture-jev"
    func recognize(image: Data) async throws -> OCRResponse { throw ModelError.emptyOCR }
    func score(original: Data, rendered: Data, text: String) async throws -> Double { throw ModelError.emptyOCR }
    func review(transcript: Transcript) async throws -> ReviewResult {
        try await gate.wait()
        return Self.result(transcript)
    }
    static func result(_ transcript: Transcript) -> ReviewResult {
        IssueAnchoring.anchor([.init(line: 1, quote: "speak", occurrence: 1, kind: .grammar,
            suggestion: "speaking", explanation: "结合上下文，此处词形需要核对。")], to: transcript)
    }
}

/// Native rendered states, independent of inference and real assignments.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_INLINE_FEEDBACK"] != nil))
@MainActor func reviewFeedbackCaptureInlineWarningsQueueAndRetry() async throws {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PAPERREVIEW_INLINE_FEEDBACK"]!)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-inline-render-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    _ = NSApplication.shared
    let oldAppearance = NSApp.appearance
    defer { NSApp.appearance = oldAppearance }
    let (store, jobs) = try await feedbackWorkspace(root: root, module: FeedbackQueueModule(), count: 1)
    let job = jobs[0]
    job.record.humanConfirmed = false
    let issues = job.record.issues
    job.record.deferredReviewIssues = issues; job.record.issues = []
    store.selectedIssueID = issues.first?.id
    for light in [false, true] {
        let host = NSHostingView(rootView: ContentView(store: store)
            .environment(\.scenePhase, .active).environment(\.colorScheme, light ? .light : .dark))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua); NSApp.appearance = window.appearance
        window.contentView = host; window.orderFront(nil)
        for (name, phase, old) in [("warnings", PipelinePhase.complete, true), ("queued-old", .queued, true),
            ("reviewing-old", .reviewing, true), ("failed-empty", .failed, false),
            ("retry-queued-empty", .queued, false), ("retry-running-empty", .reviewing, false)] {
            job.record.phase = phase; job.record.failedPhase = phase == .failed ? .reviewing : nil
            job.record.deferredReviewIssues = old ? issues : []
            try await Task.sleep(for: .milliseconds(350))
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            #expect(host.fittingSize.width <= 800)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("\(light ? "light" : "dark")-\(name).png"))
        }
        window.close()
    }
    await store.finishReadingWrites()
}

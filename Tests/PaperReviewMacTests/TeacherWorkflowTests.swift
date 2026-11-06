import AppKit
import Testing
import PaperReviewCore
@testable import PaperReview

@MainActor private func teacherWorkspace(root: URL) -> (WorkspaceStore, Assignment) {
    let store = WorkspaceStore(models: TeacherFixtureModule(), dataRoot: root)
    let transcript = LineAlignment.fallback("I feeled happy. The wether is suny.")
    var record = AssignmentRecord(title: "teacher-fixture", originalFilename: "original.png")
    record.transcript = transcript; record.phase = .complete
    record.issues = IssueAnchoring.anchor([
        .init(line: 1, quote: "feeled", occurrence: 1, kind: .spelling, suggestion: "felt", explanation: "过去式"),
        .init(line: 1, quote: "suny", occurrence: 1, kind: .spelling, suggestion: "sunny", explanation: "缺少 n")
    ], to: transcript).issues
    let job = Assignment(record: record)
    store.assignments = [job]; store.selectedID = job.id; store.selectedIssueID = record.issues.first?.id
    return (store, job)
}

@Test @MainActor func teacherResolutionUndoRedoAndCompletionPersistWithoutChangingStudentText() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-teacher-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, job) = teacherWorkspace(root: root)
    let original = job.record.transcript
    let undo = UndoManager(); undo.groupsByEvent = false
    undo.beginUndoGrouping()
    store.resolve(job, issue: job.record.issues[0], as: .annotation, undoManager: undo)
    undo.endUndoGrouping()
    await store.finishReviewWrites()
    #expect(job.record.pendingIssues.count == 1 && job.record.reviewStatus == "批阅中")
    #expect(store.selectedIssueID == job.record.issues[1].id)
    undo.undo(); await store.finishReviewWrites()
    #expect(job.record.review.decisions.isEmpty && job.record.pendingIssues.count == 2)
    #expect(store.selectedIssueID == job.record.issues[0].id)
    undo.redo(); await store.finishReviewWrites()
    #expect(job.record.review.decisions.count == 1)
    store.completeReview(job, undoManager: nil)
    #expect(!job.isReviewed)
    store.completeReview(job, keepRemaining: true, undoManager: nil)
    await store.finishReviewWrites()
    #expect(job.isReviewed && job.record.pendingIssues.isEmpty)
    let source = try #require(original)
    #expect(job.record.review.annotations(in: source).count == 1)
    #expect(job.record.transcript == original)
    let saved = try #require(await store.repository.load().first)
    #expect(saved.teacherReview == job.record.teacherReview)
    store.saveComment("很好的尝试。", job: job, undoManager: nil)
    await store.finishReviewWrites()
    #expect(!job.isReviewed && job.record.review.comment == "很好的尝试。")
}

@Test @MainActor func failedSaveRetainsTheDecisionAndBlocksCompletionUntilRetrySucceeds() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-save-failure-\(UUID())")
    try Data("fixture blocker".utf8).write(to: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, job) = teacherWorkspace(root: root)
    store.resolve(job, issue: job.record.issues[0], as: .annotation)
    await store.finishReviewWrites()
    #expect(job.record.review.decisions.count == 1 && job.reviewSaveError != nil)
    store.completeReview(job, keepRemaining: true, undoManager: nil)
    #expect(job.record.review.completedAt == nil)
    try FileManager.default.removeItem(at: root)
    store.retryReviewSave(job); await store.finishReviewWrites()
    #expect(job.reviewSaveError == nil)
    #expect(try await store.repository.load().first?.teacherReview?.decisions.count == 1)
}

@Test func legacyIgnoredSuggestionsMigrateAndCanBeRestored() throws {
    let transcript = LineAlignment.fallback("suny")
    var record = AssignmentRecord(title: "legacy", originalFilename: "original.png")
    record.transcript = transcript
    record.issues = IssueAnchoring.anchor([.init(line: 1, quote: "suny", occurrence: 1, kind: .spelling, suggestion: "sunny", explanation: "fixture")], to: transcript).issues
    record.issues[0].dismissed = true
    let reopened = try JSONDecoder().decode(AssignmentRecord.self, from: JSONEncoder().encode(record))
    #expect(reopened.pendingIssues.isEmpty && reopened.review.decisions.count == 1)
    var review = reopened.review; review.restore(reopened.issues[0])
    #expect(review.pending(reopened.issues).count == 1)
}

@Test @MainActor func readingPositionsAndFiltersRemainIndependentOfMachineCompletion() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-reading-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, job) = teacherWorkspace(root: root)
    try await store.repository.save(job.record)
    #expect(AssignmentFilter.pending.includes(job) && !AssignmentFilter.completed.includes(job))
    job.reading.presentation = "stacked"; job.reading.zoom = 1.4; job.reading.offsetY = 120
    store.saveReading(job)
    job.reading.offsetY = 220; store.saveReading(job)
    await store.finishReadingWrites()
    let position = try #require(await store.repository.readingState(id: job.id))
    #expect(position.offsetY == 220 && position.zoom == 1.4 && position.presentation == "stacked")
    let legacy = try JSONDecoder().decode(ReadingState.self, from: Data("{\"zoom\":1.2}".utf8))
    #expect(legacy.readingOffsetY == 0 && legacy.presentation == "sideBySide")
}

@MainActor private final class TeacherFixtureModule: ModelModule {
    var readiness = ModelReadiness(required: [])
    var policy: RecognitionPolicy { .init(threshold: 0.5, maximumAttempts: 3) }
    var needsTerminationPreparation: Bool { false }
    func makeSession() throws -> any ModelSession { throw ModelError.unavailable("fixture") }
    func checkReadiness() async {}
    func prepareForTermination() async {}
}

@Test @MainActor func reopeningTeacherRecordPreservesSavedDecisionsAndComment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-reopen-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, job) = teacherWorkspace(root: root)
    store.resolve(job, issue: job.record.issues[0], as: .annotation)
    await store.finishReviewWrites()
    store.saveComment("教师评语", job: job, undoManager: nil)
    await store.finishReviewWrites()
    let reopened = WorkspaceStore(models: TeacherFixtureModule(), dataRoot: root)
    await reopened.restore()
    #expect(reopened.assignments.count == 1)
    #expect(reopened.selected?.record.review.decisions.count == 1)
    #expect(reopened.selected?.record.review.comment == "教师评语")
}

@Test @MainActor func legacyDismissEntryPointUsesTheSeparateTeacherLayerAndCanRestore() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-legacy-action-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, job) = teacherWorkspace(root: root)
    let issue = job.record.issues[0]
    store.toggleDismiss(job, issueID: issue.id); await store.finishReviewWrites()
    #expect(job.record.pendingIssues.count == 1)
    #expect(job.record.review.decision(for: issue)?.resolution == .keepOriginal)
    #expect(job.record.issues[0].dismissed == false)
    store.toggleDismiss(job, issueID: issue.id); await store.finishReviewWrites()
    #expect(job.record.pendingIssues.count == 2)
}

@Test @MainActor func legacyIgnoredRecordRestoresThroughTheStoreAndSurvivesReopening() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-legacy-restore-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, job) = teacherWorkspace(root: root)
    job.record.issues[0].dismissed = true
    job.record.teacherReview = nil
    try await store.repository.save(job.record)
    let reopened = WorkspaceStore(models: TeacherFixtureModule(), dataRoot: root)
    await reopened.restore()
    let legacy = try #require(reopened.selected)
    let displayed = try #require(legacy.record.review.decisions.first)
    #expect(legacy.record.review.decisions.first?.id == displayed.id)
    reopened.restoreSuggestion(displayed, job: legacy, undoManager: nil)
    await reopened.finishReviewWrites()
    #expect(legacy.record.pendingIssues.count == 2 && legacy.record.review.decisions.isEmpty)
    let again = WorkspaceStore(models: TeacherFixtureModule(), dataRoot: root)
    await again.restore()
    #expect(again.selected?.record.pendingIssues.count == 2)
    #expect(again.selected?.record.review.decisions.isEmpty == true)
}

@Test(arguments: [false, true]) @MainActor
func staleTeacherHistoryCannotBeDeletedByRestoringAMissingSuggestion(changedRevision: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-stale-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let (store, job) = teacherWorkspace(root: root)
    store.resolve(job, issue: job.record.issues[0], as: .annotation)
    await store.finishReviewWrites()
    let decision = try #require(job.record.review.decisions.first)
    if changedRevision { job.record.transcript = LineAlignment.fallback("I felt happy. The weather is sunny.") }
    job.record.issues.removeFirst()
    let before = job.record.review
    store.restoreSuggestion(decision, job: job, undoManager: nil)
    #expect(job.record.review == before)
    #expect(!store.hasReviewWrites)
    #expect(job.record.review.decisions.count == 1)
}

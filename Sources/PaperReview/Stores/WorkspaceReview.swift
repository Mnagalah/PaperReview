import AppKit
import PaperReviewCore

extension WorkspaceStore {
    func resolve(_ job: Assignment, issue: ReviewIssue, as resolution: TeacherResolution,
                 suggestion: String? = nil, explanation: String? = nil, undoManager: UndoManager? = nil) {
        guard !job.savingReview, job.reviewSaveError == nil, activeID != job.id, !job.record.phase.isRunning, job.record.transcript?.revision == issue.revision,
              job.record.issues.contains(where: { $0.id == issue.id }), assignments.contains(where: { $0.id == job.id }) else { return }
        var review = job.record.review
        review.record(TeacherDecision(issue: issue, resolution: resolution, suggestion: suggestion, explanation: explanation))
        let next = review.pending(job.record.issues).first { $0.start >= issue.start }
            ?? review.pending(job.record.issues).first
        setReview(review, for: job, selected: next?.id, undoManager: undoManager,
            action: resolution == .annotation ? "确认批注" : "放弃建议")
    }

    func restoreSuggestion(_ decision: TeacherDecision, job: Assignment, undoManager: UndoManager?) {
        guard !job.savingReview, activeID != job.id,
              let transcript = job.record.transcript, decision.isAnchored(in: transcript),
              let target = job.record.issues.first(where: { decision.matches($0) }) else { return }
        var value = job.record.review
        value.restore(decision.issue)
        setReview(value, for: job, selected: target.id, undoManager: undoManager, action: "恢复建议")
    }

    func saveComment(_ comment: String, job: Assignment, undoManager: UndoManager?) {
        guard !job.savingReview, activeID != job.id, comment != job.record.review.comment else { return }
        var value = job.record.review; value.comment = comment; value.completedAt = nil
        setReview(value, for: job, selected: selectedIssueID, undoManager: undoManager, action: "修改评语")
    }

    func completeReview(_ job: Assignment, keepRemaining: Bool = false, undoManager: UndoManager?) {
        guard job.record.phase == .complete, activeID != job.id, !job.savingReview, job.reviewSaveError == nil,
              keepRemaining || job.record.pendingIssues.isEmpty else { return }
        var value = job.record.review
        if keepRemaining {
            for issue in value.pending(job.record.issues) { value.record(TeacherDecision(issue: issue, resolution: .keepOriginal)) }
        }
        value.completedAt = Date()
        setReview(value, for: job, selected: selectedIssueID, undoManager: undoManager, action: "完成批阅")
    }

    func reopenReview(_ job: Assignment, undoManager: UndoManager?) {
        var review = job.record.review; review.completedAt = nil
        setReview(review, for: job, selected: selectedIssueID, undoManager: undoManager, action: "继续批阅")
    }

    private func setReview(_ value: TeacherReview, for job: Assignment, selected: UUID?,
                           undoManager: UndoManager?, action: String) {
        guard assignments.contains(where: { $0.id == job.id }), activeID != job.id else { return }
        let before = job.record.review, beforeSelection = selectedIssueID
        job.record.teacherReview = value
        if selectedID == job.id { selectedIssueID = selected }
        job.reading.selectedIssueID = selected
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.select(job.id)
                target.setReview(before, for: job, selected: beforeSelection, undoManager: undoManager, action: action)
            }
        }
        undoManager?.setActionName(action)
        retryReviewSave(job)
    }

    func retryReviewSave(_ job: Assignment) {
        let previous = reviewSaves[job.id], token = UUID()
        job.reviewSaveToken = token; job.savingReview = true; job.reviewSaveError = nil
        reviewSaves[job.id] = Task {
            await previous?.value
            do {
                try await repository.save(job.record)
                if job.reviewSaveToken == token { job.reviewSaveError = nil }
            } catch {
                if job.reviewSaveToken == token { job.reviewSaveError = error.localizedDescription }
            }
            if job.reviewSaveToken == token { job.savingReview = false; reviewSaves.removeValue(forKey: job.id) }
        }
    }

    var hasReviewWrites: Bool { !reviewSaves.isEmpty }
    func finishReviewWrites() async { for task in Array(reviewSaves.values) { await task.value } }

    func saveReading(_ job: Assignment) {
        readingSaves[job.id]?.cancel()
        let token = UUID()
        job.readingSaveToken = token
        readingSaves[job.id] = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                try await repository.saveReadingState(job.reading, id: job.id)
            } catch is CancellationError {} catch { /* Reading position must not block grading or mask a review-save error. */ }
            if job.readingSaveToken == token { readingSaves.removeValue(forKey: job.id) }
        }
    }

    var hasReadingWrites: Bool { !readingSaves.isEmpty }
    func finishReadingWrites() async { for task in Array(readingSaves.values) { await task.value } }

    func selectNextPending() {
        let current = selectedID.flatMap { id in assignments.firstIndex { $0.id == id } } ?? -1
        let ordered = Array(assignments.dropFirst(current + 1)) + Array(assignments.prefix(current + 1))
        if let next = ordered.first(where: { !$0.isReviewed && $0.id != selectedID }) { select(next.id) }
    }
}

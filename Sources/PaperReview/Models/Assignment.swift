import AppKit
import Observation
import PaperReviewCore

nonisolated struct AssignmentRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var originalFilename: String
    var importedFilename: String?
    var createdAt = Date()
    var phase: PipelinePhase = .queued
    var failedPhase: PipelinePhase?
    var error: String?
    var attempt: Int = 0
    var candidates: [OCRCandidate] = []
    var transcript: Transcript?
    var issues: [ReviewIssue] = []
    var rejectedIssues: Int = 0
    var reviewRejections: [RejectedReviewIssue]?
    var deferredReviewIssues: [ReviewIssue]?
    var humanConfirmed = false
    var width: Int = 1
    var height: Int = 1
    var isExample = false
    var rendererVersion = "native-plain-flow-v3"
    var phaseDurations: [String: Double] = [:]
    var wordChecksCompleted: Int?
    var wordChecksTotal: Int?
    var structureVersion: String?
    var pageAnnotations: [PageAnnotation]?
    var teacherReview: TeacherReview?
    var activeIssues: [ReviewIssue] { issues.filter { !$0.dismissed } }
    var review: TeacherReview {
        if let teacherReview { return teacherReview }
        var value = TeacherReview()
        value.decisions = issues.filter(\.dismissed).map { issue in
            var decision = TeacherDecision(issue: issue, resolution: .keepOriginal)
            decision.id = issue.id
            return decision
        }
        return value
    }
    var pendingIssues: [ReviewIssue] { review.pending(issues) }
    var reviewStatus: String {
        if review.completedAt != nil { return "已批阅" }
        if !review.decisions.isEmpty || !review.comment.isEmpty { return "批阅中" }
        return "待批阅"
    }
    var displayFilename: String {
        if let importedFilename { return importedFilename }
        let ext = (originalFilename as NSString).pathExtension
        return ext.isEmpty ? title : title + "." + ext
    }
    var score: Double? { candidates.first { $0.transcript.revision == transcript?.revision }?.score }
    mutating func restoreInterruptedPhase() {
        if phase == .needsConfirmation {
            failedPhase = .reviewing; phase = .cancelled; error = nil
        } else if phase.isRunning || phase == .queued {
            failedPhase = phase; phase = .cancelled
        }
    }
}

@Observable final class Assignment: Identifiable {
    var record: AssignmentRecord
    var page: PreparedPage?
    var sourceImage: NSImage?
    var enhancedImage: NSImage?
    var reading = ReadingState()
    var savingReview = false
    var reviewSaveError: String?
    var reviewSaveToken: UUID?
    var readingSaveToken: UUID?
    var isReviewed: Bool { record.review.completedAt != nil && !savingReview && reviewSaveError == nil }
    var id: UUID { record.id }
    var hasPoorReadability: Bool {
        guard ![.preparing, .recognizing, .verifyingWords].contains(record.phase), let page, let transcript = record.transcript,
              let candidate = record.candidates.first(where: { $0.transcript.revision == transcript.revision }),
              candidate.scoredSourceVersion == page.scan.version else { return false }
        return candidate.readability?.needsAssistance(verification: candidate.wordVerification, score: candidate.score) == true
    }
    var recoverableReviewCount: Int {
        guard let transcript = record.transcript, let rejections = record.reviewRejections else { return 0 }
        let result = IssueAnchoring.anchor(rejections.map(\.proposal), to: transcript, recoverUniqueOccurrence: true, recoverUniqueLine: true)
        return result.recoveredOccurrences.count + result.recoveredLines.count
    }
    var wordRegions: [WordRegion] {
        guard let transcript = record.transcript, let page else { return [] }
        return WordAlignment.inventory(transcript, hints: page.words).regions
    }
    var unlocatedTextRanges: [NSRange] {
        guard !record.humanConfirmed, let transcript = record.transcript, let page else { return [] }
        return WordAlignment.inventory(transcript, hints: page.words).unlocatedRanges
    }
    var uncertainWordRects: [PageRect] {
        guard !record.humanConfirmed, let transcript = record.transcript else { return [] }
        return record.candidates.first { $0.transcript.revision == transcript.revision }?.uncertainWordRects ?? []
    }
    var uncertainLineIDs: [Int] {
        guard !record.humanConfirmed, let transcript = record.transcript, let page else { return [] }
        if let candidate = record.candidates.first(where: { $0.transcript.revision == transcript.revision }),
           let uncertain = candidate.uncertainLineIDs { return uncertain }
        return LineAlignment.uncertainLines(transcript, hints: page.hints)
    }
    init(record: AssignmentRecord) { self.record = record }
    func setPage(_ page: PreparedPage) {
        self.page = page
        sourceImage = NSImage(data: page.source)
        enhancedImage = NSImage(data: page.enhanced)
        record.width = page.width; record.height = page.height
    }
}

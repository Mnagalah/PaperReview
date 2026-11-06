import SwiftUI
import PaperReviewCore

struct UnadoptedReviewView: View {
    let store: WorkspaceStore
    let job: Assignment
    private func unadoptedCount(_ job: Assignment) -> Int {
        job.record.rejectedIssues + (job.record.deferredReviewIssues?.count ?? 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("未采用的建议").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if job.record.reviewRejections == nil && job.record.rejectedIssues > 0 {
                        Text("这条旧记录只保存了数量，没有保存具体原因。重新审核后可查看详情。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(job.record.reviewRejections ?? []) { rejection in
                        let reason = currentReason(rejection, job: job)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reason.title).font(.callout.weight(.semibold))
                            Text("\(rejection.proposal.quote.isEmpty ? "（没有原词引用）" : rejection.proposal.quote) → \(rejection.proposal.suggestion)")
                                .font(.body).textSelection(.enabled)
                            if reason == .invalidLine || reason == .quoteNotFound || reason == .occurrenceOutOfBounds {
                                Text("模型指定第 \(rejection.proposal.line) 行，第 \(rejection.proposal.occurrence) 次出现。")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(job.record.deferredReviewIssues ?? []) { issue in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("词区识别仍有分歧，暂不批注").font(.callout.weight(.semibold))
                            Text("\(issue.quote) → \(issue.suggestion)").font(.body).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 320)
            if job.recoverableReviewCount > 0 {
                Button("重新定位 \(job.recoverableReviewCount) 条建议") {
                    store.reanchorReview(job)
                }.disabled(store.activeID != nil)
            }
        }
    }
    private func currentReason(_ rejection: RejectedReviewIssue, job: Assignment) -> ReviewRejectionReason {
        guard let transcript = job.record.transcript else { return rejection.reason }
        return IssueAnchoring.anchor([rejection.proposal], to: transcript).rejections.first?.reason ?? rejection.reason
    }
}

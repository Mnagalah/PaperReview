import SwiftUI
import PaperReviewCore

/// Invalid model proposals stay readable in the list, without fabricated anchors.
struct ReviewRejectedRows: View {
    let store: WorkspaceStore
    let job: Assignment
    var body: some View {
        ForEach(job.record.reviewRejections ?? []) { rejection in
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(rejection.proposal.kind.title)
                    Spacer()
                    Text("建议待核对").foregroundStyle(Color(nsColor: WorkspaceStyle.warningColor))
                }.font(.system(size: 11, weight: .medium))
                Text("\(rejection.proposal.quote.isEmpty ? "（未引用原词）" : rejection.proposal.quote) → \(rejection.proposal.suggestion.isEmpty ? "建议删除" : rejection.proposal.suggestion)")
                    .font(.system(size: 16, weight: .medium)).textSelection(.enabled)
                Text(rejection.reason.title).font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .overlay(alignment: .bottom) { Divider().padding(.horizontal, 14) }
        }
        if job.record.reviewRejections == nil && job.record.rejectedIssues > 0 {
            Text("另有 \(job.record.rejectedIssues) 条旧建议未保存详情，可重新审核。")
                .font(.callout).foregroundStyle(.secondary).padding(14)
        }
        if job.recoverableReviewCount > 0 {
            Button("重新定位 \(job.recoverableReviewCount) 条建议") { store.reanchorReview(job) }
                .buttonStyle(.borderless).padding(14)
                .disabled(store.activeID != nil || job.record.phase.isPendingOrRunning)
        }
    }
}

import SwiftUI
import PaperReviewCore

/// Each responsive candidate owns its popover and anchors it to the button.
/// Active processing stays expanded instead of requiring an extra click.
struct ProcessingStatusView: View {
    let store: WorkspaceStore
    let job: Assignment
    let mode: ComparisonMode
    @State private var details = false

    var body: some View {
        if job.record.phase.isRunning {
            HStack(spacing: 10) {
                stages(inline: true).frame(minWidth: 300, maxWidth: 440)
                if store.activeID == job.id {
                    Button { store.cancel() } label: { Image(systemName: "pause.fill") }
                        .help("暂停处理").accessibilityLabel("暂停处理")
                }
            }
        } else {
            Button { details = true } label: {
                HStack(spacing: 6) {
                    Text(job.record.phase == .complete ? "分析完成" : job.record.phase.title)
                    Image(systemName: "chevron.down").font(.caption2)
                }.fixedSize()
            }
            .help("查看处理详情")
            .popover(isPresented: $details, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    stages(inline: false)
                    if job.record.phase == .complete {
                        Button("重新识别这张照片") { details = false; store.retry(job, entireOCR: true) }
                    }
                }.padding(16).frame(width: 480)
            }
        }
    }

    private func stages(inline: Bool) -> some View {
        StageStrip(record: job.record, comparisonMode: .constant(mode), threshold: store.models.policy.threshold,
            canRetryOCR: store.activeID != job.id && !job.record.phase.isRunning,
            onRetryOCR: { store.retry(job, entireOCR: true) }, showsLayoutPicker: false, inline: inline)
    }
}

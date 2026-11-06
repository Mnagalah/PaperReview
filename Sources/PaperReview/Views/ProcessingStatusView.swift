import SwiftUI
import PaperReviewCore

/// The stage rail retains the same identity and trailing edge through completion.
struct ProcessingStatusView: View {
    let store: WorkspaceStore
    let job: Assignment
    let mode: ComparisonMode

    var body: some View {
        HStack(spacing: 6) {
            StageStrip(record: job.record, comparisonMode: .constant(mode), threshold: store.models.policy.threshold,
                canRetryOCR: store.activeID != job.id && !job.record.phase.isPendingOrRunning && !job.savingReview && job.reviewSaveError == nil,
                onRetryOCR: { store.retry(job, entireOCR: true) }, showsLayoutPicker: false, inline: true)
            Button { store.cancel() } label: { Image(systemName: "pause.fill").frame(width: 18, height: 28) }
                .help("暂停处理").accessibilityLabel("暂停处理")
                .disabled(store.activeID != job.id)
                .opacity(job.record.phase.isRunning ? 1 : 0)
                .accessibilityHidden(!job.record.phase.isRunning)
        }.frame(height: 32)
    }
}

/// A clipped, fixed-width two-page label: completion never changes its footprint.
struct AnalysisStatusLabel: View {
    let phase: PipelinePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pageHeight: CGFloat = 18
    static func title(for phase: PipelinePhase) -> String {
        phase == .queued ? "排队中" : phase.isRunning ? "分析中" : phase == .complete ? "分析完成" : phase.title
    }
    var body: some View {
        Group {
            if phase.isRunning || phase == .complete {
                if reduceMotion {
                    Text(Self.title(for: phase))
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("分析中").frame(height: pageHeight)
                        Text("分析完成").frame(height: pageHeight)
                    }
                    .offset(y: phase == .complete ? -pageHeight : 0)
                    .frame(height: pageHeight, alignment: .top)
                    .clipped()
                    .animation(WorkspaceMotion.progressTransition, value: phase == .complete)
                }
            } else { Text(Self.title(for: phase)) }
        }.frame(width: 60, height: pageHeight, alignment: .trailing)
            .accessibilityElement(children: .ignore).accessibilityLabel(Self.title(for: phase))
    }
}

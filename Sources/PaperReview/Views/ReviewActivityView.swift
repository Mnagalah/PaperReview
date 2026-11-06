import SwiftUI
import PaperReviewCore

/// One state mapping for empty results, old results, and failure retries.
struct ReviewActivity: Equatable {
    let title: String
    let isBusy: Bool
    let isQueued: Bool
    let canRetry: Bool
    init?(record: AssignmentRecord) {
        let phase = record.phase
        guard phase != .complete else { return nil }
        isQueued = phase == .queued
        isBusy = phase.isPendingOrRunning
        canRetry = !isBusy
        switch phase {
        case .queued: title = "等待队列中"
        case .reviewing: title = "正在检查基础错误"
        case .failed: title = record.failedPhase == .reviewing ? "基础审核未完成" : "分析尚未完成"
        case .cancelled: title = "处理已暂停"
        default: title = phase.title
        }
    }
}

struct ReviewActivityView: View {
    let activity: ReviewActivity
    let compact: Bool
    var waitingForOther = false
    let retry: () -> Void
    var body: some View {
        if compact {
            HStack(spacing: 6) {
                if activity.isBusy { LiquidDotsLoader().scaleEffect(0.45).frame(width: 32, height: 18) }
                Text(activity.title).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if activity.canRetry { Button("重试") { retry() }.buttonStyle(.borderless).font(.system(size: 12)) }
            }.accessibilityElement(children: .contain)
        } else {
            VStack(spacing: 12) {
                if activity.isBusy { LiquidDotsLoader() }
                Text(activity.title).font(.system(size: 14, weight: .medium))
                if activity.isQueued {
                    Text(waitingForOther ? "前一份作业完成后会自动开始。" : "即将开始处理。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if activity.canRetry { Button("继续处理") { retry() }.buttonStyle(.borderless) }
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
    }
}

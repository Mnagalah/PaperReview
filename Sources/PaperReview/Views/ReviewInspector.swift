import SwiftUI
import PaperReviewCore

struct ReviewInspector: View {
    @Bindable var store: WorkspaceStore
    let job: Assignment?
    @State private var showDismissed = false
    @State private var showingUnadopted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("基础审核").font(.system(size: 16, weight: .semibold))
                Spacer()
                if let job, job.record.phase == .reviewing { ProgressView().controlSize(.small) }
                if let job, job.record.phase == .complete {
                    Text("\(job.record.activeIssues.count) 条建议").font(.system(size: 13)).monospacedDigit()
                        .foregroundStyle(.secondary).fixedSize()
                    Menu {
                        Toggle("显示已忽略建议", isOn: $showDismissed)
                        Button("重新审核") { store.retry(job) }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)).frame(width: 28, height: 28) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("审核选项")
                }
            }.padding(.horizontal, 20).frame(height: 60)
            Divider()
            if let job {
                if job.record.phase == .complete {
                    completed(job)
                } else {
                    VStack(alignment: .leading, spacing: 15) {
                        Text(inspectorTitle(job)).font(.headline)
                        if job.record.phase == .failed && job.record.failedPhase == .reviewing {
                            Button("重试基础审核") { store.retry(job) }.disabled(store.activeID == job.id)
                        }
                        if job.record.phase == .needsConfirmation {
                            Button("继续基础审核") { store.retry(job) }.disabled(store.activeID == job.id)
                        }
                    }.padding(20)
                    Spacer()
                }
            } else {
                Text("等待作业")
                    .font(.callout).foregroundStyle(.secondary).padding(20)
                Spacer()
            }
        }.background(WorkspaceStyle.panel)
    }

    private func completed(_ job: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if unadoptedCount(job) > 0 {
                Button { showingUnadopted = true } label: {
                    HStack {
                        Text("\(unadoptedCount(job)) 条建议未采用")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .popover(isPresented: $showingUnadopted) { unadoptedDetails(job).padding(20).frame(width: 380) }
                Divider().padding(.horizontal, 22)
            }
            if job.record.activeIssues.isEmpty && !showDismissed {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: unadoptedCount(job) > 0 ? "text.bubble" : "checkmark.circle").font(.title2).foregroundStyle(.secondary)
                    Text(unadoptedCount(job) > 0 ? "暂无可用批注" : "未发现明确的基础错误").font(.headline)
                    if unadoptedCount(job) > 0 { Button("重新审核") { store.retry(job) } }
                }.padding(20)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(job.record.issues.filter { showDismissed || !$0.dismissed }.sorted { $0.start < $1.start }) { issue in
                                issueRow(issue, job: job).id(issue.id)
                                Divider().padding(.horizontal, 22)
                            }
                        }
                    }
                    .onChange(of: store.selectedIssueID) { _, value in
                        if let value { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(value, anchor: .center) } }
                    }
                }
            }
        }
    }
    private func unadoptedCount(_ job: Assignment) -> Int {
        job.record.rejectedIssues + (job.record.deferredReviewIssues?.count ?? 0)
    }
    private func unadoptedDetails(_ job: Assignment) -> some View {
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
                    showingUnadopted = false; store.reanchorReview(job)
                }.disabled(store.activeID != nil)
            }
            Button("重新审核") { showingUnadopted = false; store.retry(job) }.disabled(store.activeID == job.id)
        }
    }
    private func currentReason(_ rejection: RejectedReviewIssue, job: Assignment) -> ReviewRejectionReason {
        guard let transcript = job.record.transcript else { return rejection.reason }
        return IssueAnchoring.anchor([rejection.proposal], to: transcript).rejections.first?.reason ?? rejection.reason
    }
    private func issueRow(_ issue: ReviewIssue, job: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(issue.kind.title, systemImage: issue.kind == .spelling ? "character.cursor.ibeam" : "textformat.abc")
                    .font(.caption.weight(.medium)).foregroundStyle(issue.kind == .spelling ? Color.red : Color.orange)
                Spacer()
                Text("第 \(issue.lineID) 行").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Button { store.selectedIssueID = issue.id } label: {
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(issue.quote).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(issue.suggestion.isEmpty ? "建议删除" : issue.suggestion)
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(issue.quote).foregroundStyle(.secondary).lineLimit(4)
                            Label(issue.suggestion.isEmpty ? "建议删除" : issue.suggestion, systemImage: "arrow.turn.down.right")
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    Text(issue.explanation).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("在照片中定位原词")
            HStack {
                if issue.dismissed { Text("已忽略").foregroundStyle(.secondary) }
                Spacer()
                Button(issue.dismissed ? "恢复建议" : "忽略") { store.toggleDismiss(job, issueID: issue.id) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }.font(.caption)
        }
        .padding(.horizontal, 22).padding(.vertical, 19)
        .background(store.selectedIssueID == issue.id ? WorkspaceStyle.selection.opacity(0.5) : Color.clear)
    }
    private func inspectorTitle(_ job: Assignment) -> String {
        switch job.record.phase {
        case .reviewing: "正在检查基础错误"
        case .needsConfirmation: "可继续基础审核"
        case .scoring: "等待 Jev 复核"
        case .failed: "审核尚未完成"
        case .cancelled: "处理已暂停"
        default: "等待忠实转写"
        }
    }
}

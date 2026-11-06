import SwiftUI
import AppKit
import PaperReviewCore

struct ReviewInspector: View {
    @Bindable var store: WorkspaceStore
    let job: Assignment?
    @Binding var processed: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingUnadopted = false
    @State private var showingDiscarded = false
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let job {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Picker("建议列表", selection: $processed) {
                            Text("已发现问题 \(job.record.pendingIssues.count)").tag(false)
                            Text("已确认项 \(job.record.review.confirmed.count)").tag(true)
                        }.pickerStyle(.segmented).controlSize(.large).labelsHidden()
                        Spacer(minLength: 0)
                        Button { showingDiscarded = true } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).frame(width: 24, height: WorkspaceGrid.controlHeight)
                            .help("已放弃的问题（\(job.record.review.discarded.count)）")
                            .accessibilityLabel("已放弃的问题，\(job.record.review.discarded.count) 项")
                            .disabled(job.record.review.discarded.isEmpty)
                        .popover(isPresented: $showingDiscarded, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("已放弃的问题").font(.headline).padding(.horizontal, 18)
                                history(job, resolution: .keepOriginal)
                            }.padding(.vertical, 20).frame(width: 340, height: 360)
                        }
                    }.frame(height: WorkspaceGrid.controlHeight)
                        .padding(.horizontal, WorkspaceGrid.paneInset).padding(.top, 8)
                    if unadoptedCount(job) > 0 { unadoptedButton(job) }
                }.frame(height: WorkspaceGrid.contextHeight, alignment: .top)
                if processed { history(job, resolution: .annotation) }
                else if !job.record.pendingIssues.isEmpty { suggestions(job) }
                else { emptyState(job) }
            } else {
                Text("导入作业后，建议会显示在这里。").font(.callout).foregroundStyle(.secondary).padding(20)
                Spacer()
            }
        }
        .background {
            WorkspaceStyle.panel.opacity(reduceTransparency || contrast == .increased ? 1 : colorScheme == .light ? 0.86 : 0.3)
                .ignoresSafeArea()
        }
        .onChange(of: job?.id) { _, _ in showingUnadopted = false; showingDiscarded = false }
    }

    private func unadoptedButton(_ job: Assignment) -> some View {
        Button { showingUnadopted = true } label: {
            HStack(spacing: 8) {
                Text("\(unadoptedCount(job)) 条模型建议未采用")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2)
            }.frame(maxWidth: .infinity).frame(height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.horizontal, WorkspaceGrid.paneInset)
            .popover(isPresented: $showingUnadopted, arrowEdge: .top) {
                UnadoptedReviewView(store: store, job: job).padding(20).frame(width: 380)
            }
    }

    private func suggestions(_ job: Assignment) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(job.record.pendingIssues) { issue in issueRow(issue, job: job).id(issue.id) }
                }.background(ReviewScrollAppearance())
                    .padding(.horizontal, WorkspaceGrid.paneInset)
                    .padding(.top, WorkspaceGrid.paneInset).padding(.bottom, 16)
            }
            .focusable().focused($listFocused)
            .onKeyPress(.downArrow) { moveSelection(job, by: 1); return .handled }
            .onKeyPress(.upArrow) { moveSelection(job, by: -1); return .handled }
            .onChange(of: store.selectedIssueID) { _, id in
                if let id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
        }
    }
    private func issueRow(_ issue: ReviewIssue, job: Assignment) -> some View {
        let selected = store.selectedIssueID == issue.id
        return VStack(alignment: .leading, spacing: 14) {
            Button { store.selectedIssueID = issue.id } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(issue.kind.title)
                            .foregroundStyle(issue.kind == .spelling ? Color(nsColor: WorkspaceStyle.spellingColor) : Color(nsColor: WorkspaceStyle.grammarColor))
                        Spacer()
                        Text("第 \(issue.lineID) 行").foregroundStyle(.secondary)
                    }.font(.system(size: 11, weight: .medium))
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(issue.quote).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(issue.suggestion.isEmpty ? "建议删除" : issue.suggestion)
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(issue.quote).foregroundStyle(.secondary)
                            Label(issue.suggestion.isEmpty ? "建议删除" : issue.suggestion, systemImage: "arrow.turn.down.right")
                        }
                    }.font(.system(size: 16, weight: selected ? .semibold : .medium))
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("定位原稿与识别稿中的问题词")
                .accessibilityAddTraits(selected ? .isSelected : [])
            if selected {
                if let transcript = job.record.transcript, let context = ReviewSentence.context(for: issue, in: transcript) {
                    Text(contextText(context)).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                }
                Text(issue.explanation).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("确认") { store.resolve(job, issue: issue, as: .annotation, undoManager: undoManager) }
                        .buttonStyle(WorkspacePrimaryButtonStyle())
                    Button("放弃") { store.resolve(job, issue: issue, as: .keepOriginal, undoManager: undoManager) }
                        .buttonStyle(.borderless)
                }.controlSize(.regular).disabled(store.activeID == job.id || job.savingReview)
            }
        }.padding(14)
            .background(selected ? WorkspaceStyle.selection.opacity(0.38) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if selected && contrast == .increased {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(WorkspaceStyle.border, lineWidth: 1)
                }
            }
            .overlay(alignment: .bottom) { if !selected { Divider().padding(.horizontal, 14) } }
    }
    private func contextText(_ context: ReviewSentence) -> AttributedString {
        let value = NSMutableAttributedString(string: context.text)
        value.addAttributes([.foregroundColor: WorkspaceStyle.photoFocusColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: context.quoteRange)
        return AttributedString(value)
    }
    private func history(_ job: Assignment, resolution: TeacherResolution) -> some View {
        let decisions = resolution == .annotation ? job.record.review.confirmed : job.record.review.discarded
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(decisions.sorted { $0.issue.start < $1.issue.start }) { decision in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(decision.resolution == .annotation ? "已确认" : "已放弃",
                                systemImage: decision.resolution == .annotation ? "checkmark" : "xmark")
                            Spacer()
                            if job.record.transcript.map({ decision.isAnchored(in: $0) }) != true {
                                Text("位置待确认").foregroundStyle(Color(nsColor: WorkspaceStyle.warningColor))
                            }
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(decision.issue.quote).font(.system(size: 16, weight: .medium)).textSelection(.enabled)
                        if decision.resolution == .annotation {
                            Text(decision.suggestion.isEmpty ? "建议删除" : decision.suggestion).font(.system(size: 14))
                            Text(decision.explanation).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        if job.record.transcript.map({ decision.isAnchored(in: $0) }) == true,
                           job.record.issues.contains(where: { decision.matches($0) }) {
                            Button("重新确认") {
                                store.restoreSuggestion(decision, job: job, undoManager: undoManager)
                                showingDiscarded = false
                            }
                                .buttonStyle(.borderless).font(.system(size: 12)).disabled(job.savingReview || store.activeID == job.id)
                        } else { Text("历史记录").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }.padding(18)
                    Divider().padding(.horizontal, 18)
                }
                if decisions.isEmpty { Text(resolution == .annotation ? "暂无已确认项" : "暂无已放弃的问题").font(.callout).foregroundStyle(.secondary).padding(20) }
            }.background(ReviewScrollAppearance())
        }
    }
    private func emptyState(_ job: Assignment) -> some View {
        VStack(spacing: 12) {
            if job.record.phase == .complete {
                Image(systemName: job.isReviewed ? "checkmark.circle" : "text.bubble").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                Text(job.isReviewed ? "这份作业已批阅" : job.record.review.decisions.isEmpty ? "未发现明确的基础错误" : "没有待确认的问题")
                    .font(.system(size: 15, weight: .semibold))
                if !job.isReviewed { Text("可在顶部确认完成批阅。").font(.callout).foregroundStyle(.secondary) }
            } else {
                if job.record.phase.isRunning { LiquidDotsLoader() }
                Text(job.record.phase == .reviewing ? "正在检查基础错误" : job.record.phase == .failed ? "分析尚未完成" : job.record.phase == .cancelled ? "处理已暂停" : "等待识别稿")
                    .font(.system(size: 14, weight: .medium))
                if job.record.phase == .failed || job.record.phase == .cancelled {
                    Button("继续处理") { store.retry(job) }.disabled(store.activeID == job.id)
                }
            }
            Spacer()
        }.multilineTextAlignment(.center).padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private func moveSelection(_ job: Assignment, by delta: Int) {
        let issues = job.record.pendingIssues
        guard !issues.isEmpty else { return }
        let index = issues.firstIndex { $0.id == store.selectedIssueID } ?? (delta > 0 ? -1 : issues.count)
        store.selectedIssueID = issues[min(issues.count - 1, max(0, index + delta))].id
    }
    private func unadoptedCount(_ job: Assignment) -> Int { job.record.rejectedIssues + (job.record.deferredReviewIssues?.count ?? 0) }
}

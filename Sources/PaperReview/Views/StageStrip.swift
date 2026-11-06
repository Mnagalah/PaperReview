import SwiftUI
import PaperReviewCore

struct StageStrip: View {
    let record: AssignmentRecord
    @Binding var comparisonMode: ComparisonMode
    let threshold: Double
    let canRetryOCR: Bool
    let onRetryOCR: () -> Void
    var showsLayoutPicker = true
    var inline = false
    var body: some View {
        HStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                stages(compact: false)
                stages(compact: true)
            }
            if !inline { Spacer(minLength: 0) }
            if showsLayoutPicker { Picker("对照方式", selection: $comparisonMode) {
                ForEach(ComparisonMode.allCases) { mode in
                    Image(systemName: mode.symbol).tag(mode).help(mode.title).accessibilityLabel(mode.title)
                }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 112).accessibilityLabel("对照方式") }
        }.font(.system(size: inline ? 12 : 14)).padding(.horizontal, inline ? 0 : 22).frame(height: inline ? 32 : 60)
            .background { if !inline { WorkspaceStyle.panel } }
    }
    private func stages(compact: Bool) -> some View {
        HStack(spacing: inline ? 8 : 12) {
            item("照片", phase: .preparing, complete: record.width > 1, compact: compact)
            separator
            item(transcriptionTitle, phase: record.phase == .verifyingWords ? .verifyingWords : .recognizing, complete: record.transcript != nil, compact: compact)
            separator
            JevStageButton(record: record, threshold: threshold, canRetryOCR: canRetryOCR, onRetryOCR: onRetryOCR) {
                item(compact ? "Jev" : "Jev 复核",
                    phase: .scoring, complete: record.score != nil || record.humanConfirmed, compact: false)
            }
            separator
            item("基础审核", phase: .reviewing, complete: record.phase == .complete, compact: compact)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var transcriptionTitle: String {
        if record.phase == .verifyingWords {
            return "逐词 \(record.wordChecksCompleted ?? 0)/\(record.wordChecksTotal ?? 0)"
        }
        return record.phase == .recognizing && record.attempt > 1 ? "转写 · 第 \(record.attempt) 次" : "转写"
    }
    private var separator: some View { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
    private func item(_ title: String, phase: PipelinePhase, complete: Bool, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if record.phase == phase { ProgressView().controlSize(.small) }
                else if record.phase == .failed && record.failedPhase == phase { Image(systemName: "exclamationmark.circle").foregroundStyle(Color(nsColor: WorkspaceStyle.warningColor)) }
                else { Image(systemName: complete ? "checkmark.circle.fill" : "circle").foregroundStyle(complete ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.5)) }
            }.frame(width: 17)
            if !compact || record.phase == phase {
                Text(title).fontWeight(record.phase == phase ? .semibold : .medium).fixedSize().monospacedDigit()
                    .foregroundStyle(record.phase == phase || complete ? Color.primary : Color.secondary)
            }
            if inline, phase == .verifyingWords, record.phase == .verifyingWords,
               let total = record.wordChecksTotal, total > 0 {
                ProgressView(value: Double(max(0, min(record.wordChecksCompleted ?? 0, total))), total: Double(total))
                    .progressViewStyle(.linear).frame(width: 48).accessibilityLabel("逐词识别进度")
            }
        }.accessibilityElement(children: .combine).accessibilityLabel(title).help(title)
    }
}

/// Each ViewThatFits candidate owns its own presentation state. A shared
/// popover binding would let two mounted candidate views present at once.
private struct JevStageButton<Label: View>: View {
    let record: AssignmentRecord
    let threshold: Double
    let canRetryOCR: Bool
    let onRetryOCR: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var showingDetails = false
    var body: some View {
        Button { showingDetails = true } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(record.attempt == 0 && record.candidates.isEmpty)
            .help("查看 Jev 识别详情")
            .popover(isPresented: $showingDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Jev 识别一致性").font(.headline)
                    ForEach(record.candidates) { candidate in
                        HStack {
                            Text("第 \(candidate.attempt) 次")
                            if let version = candidate.scoredSourceVersion, version != PhotoProcessor.version {
                                Text("历史扫描").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(candidate.score.map { String(format: "%.4f", $0) } ?? "尚未评分").monospacedDigit()
                        }.help(candidate.scoredSourceVersion.map { "评分时的扫描版本：\($0)" } ?? "此前保存的识别分数，未记录扫描版本。")
                    }
                    Divider()
                    Text("复识参考分 \(threshold, specifier: "%.2f") · 试验值")
                    Text("逐词核验稳定时继续审核；其余低分结果自动复识。分数不是作文成绩或识别准确率。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("重新识别这张照片") { showingDetails = false; onRetryOCR() }
                        .disabled(!canRetryOCR)
                }.padding(20).frame(width: 320)
            }
    }
}

import SwiftUI
import AppKit
import PaperReviewCore

struct ComparisonView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var job: Assignment
    @State private var enhanced = true
    @State private var zoom = 1.0
    @State private var editing = false
    @AppStorage("comparisonMode") private var comparisonModeRaw = ComparisonMode.sideBySide.rawValue
    @AppStorage("showRecognitionUncertainty") private var showUncertainty = true
    @AppStorage("comparisonWipeFraction") private var wipeFraction = 0.5

    private var comparisonMode: Binding<ComparisonMode> {
        Binding(get: { ComparisonMode(rawValue: comparisonModeRaw) ?? .sideBySide }, set: { comparisonModeRaw = $0.rawValue })
    }

    private var selectedIssue: ReviewIssue? { job.record.issues.first { $0.id == store.selectedIssueID && !$0.dismissed } }
    var body: some View {
        VStack(spacing: 0) {
            StageStrip(record: job.record, comparisonMode: comparisonMode,
                threshold: store.models.policy.threshold,
                canRetryOCR: store.activeID != job.id && !job.record.phase.isRunning,
                onRetryOCR: { store.retry(job, entireOCR: true) })
            Divider()
            if job.record.phase == .needsConfirmation || job.record.phase == .failed || job.record.phase == .cancelled {
                recoveryBanner
                Divider()
            }
            if job.hasPoorReadability {
                Label { Text("这份作业可读性较差") } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }.font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.vertical, 10)
                    .help("识别存在较多疑义，可核对原文后重新审核。")
                Divider()
            }
            HStack(alignment: .center, spacing: 22) {
                HStack {
                    Picker("照片显示", selection: $enhanced) {
                        Text("扫描增强").tag(true); Text("原色").tag(false)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 145)
                    Spacer(minLength: 0)
                    Button { store.showOriginal(job) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("查看完整原照片")
                }.frame(maxWidth: .infinity)
                HStack {
                    Text("识别原文").font(.system(size: 15, weight: .semibold)).fixedSize()
                    if let transcript = job.record.transcript, !transcript.isFullyAligned {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                            .help(transcript.isAligned ? "按检测到的位置对照；词区边界可能有误差。" : "没有取得可靠的行对应。原文仍保留，可复制全文或打开编辑原文。")
                            .accessibilityLabel(transcript.isAligned ? "部分未对齐" : "未对齐")
                    }
                    Toggle("疑义标记", isOn: $showUncertainty).toggleStyle(.switch).controlSize(.small).font(.caption)
                        .fixedSize().help("紫色表示识别存在分歧或没有可靠定位；不改变原文和审核结果。")
                    Spacer(minLength: 0)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(job.record.transcript?.text ?? "", forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .help("复制忠实原文").disabled(job.record.transcript == nil)
                    Button(job.hasPoorReadability ? "核对原文" : "编辑原文") { editing = true }
                        .disabled(job.record.transcript == nil || store.activeID == job.id)
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 22).padding(.vertical, 15)
                .background(WorkspaceStyle.panel)
            PairedDocumentView(image: enhanced ? job.enhancedImage : job.sourceImage,
                transcript: job.record.transcript, issues: job.record.activeIssues,
                uncertainLineIDs: showUncertainty ? job.uncertainLineIDs : [], wordRegions: job.wordRegions,
                uncertainWordRects: showUncertainty ? job.uncertainWordRects : [],
                unlocatedTextRanges: showUncertainty ? job.unlocatedTextRanges : [],
                selectedIssueID: store.selectedIssueID,
                aspect: Double(job.record.height) / Double(max(1, job.record.width)), zoom: zoom,
                mode: comparisonMode.wrappedValue, wipeFraction: wipeFraction,
                onZoomChange: { zoom = $0 }, onWipeChange: { wipeFraction = $0 }, onLineClick: { lineID in
                    store.selectedIssueID = job.record.activeIssues.first { $0.lineID == lineID }?.id
                }, onIssueClick: { store.selectedIssueID = $0 }).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WorkspaceStyle.canvas)
            Divider()
            HStack(spacing: 12) {
                if job.record.humanConfirmed { Text("已核对") }
                Spacer()
                if store.activeID == job.id { Button("暂停") { store.cancel() } }
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $zoom, in: 0.75...2).frame(width: 100).accessibilityLabel("对照缩放")
                Button("\(Int(zoom * 100))%") { zoom = 1 }.monospacedDigit().buttonStyle(.borderless).frame(width: 50)
            }.font(.caption).padding(.horizontal, 22).padding(.vertical, 10)
                .background(WorkspaceStyle.panel)
        }
        .sheet(isPresented: $editing) { TranscriptEditor(store: store, job: job) }
    }

    private var recoveryBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: job.record.phase == .cancelled ? "pause.circle" : "exclamationmark.triangle").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.record.phase == .needsConfirmation ? "识别结果已保留，可继续基础审核" : job.record.phase == .cancelled ? "处理已暂停，已有结果仍保留" : "\(job.record.failedPhase == .recognizing || job.record.failedPhase == .verifyingWords ? "识别" : job.record.failedPhase == .scoring ? "Jev 复核" : job.record.failedPhase == .reviewing ? "基础审核" : "照片处理")未完成")
                    .font(.callout.weight(.semibold))
                Text(job.record.phase == .needsConfirmation ? "原文编辑为可选操作。" : job.record.error ?? "可继续未完成的阶段。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(job.record.phase == .needsConfirmation ? "继续基础审核" : "重试此阶段") { store.retry(job) }.disabled(store.activeID == job.id)
        }.padding(.horizontal, 22).padding(.vertical, 14).background(Color.orange.opacity(0.07))
    }

}

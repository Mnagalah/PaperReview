import SwiftUI
import AppKit
import PaperReviewCore

struct ComparisonView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var job: Assignment
    @Environment(\.undoManager) private var undoManager
    @State private var enhanced = true
    @Binding var editing: Bool
    @State private var annotationPreview = false
    @AppStorage("showRecognitionUncertainty") private var showUncertainty = false
    @AppStorage("showProblemMarks") private var showMarks = true
    @AppStorage("readingFontSize") private var fontSize = 18.0
    private var presentation: String { job.reading.presentation }
    private var isReading: Bool { presentation == "reading" }
    private var mode: ComparisonMode { ComparisonMode(rawValue: presentation) ?? .sideBySide }
    private var visibleIssues: [ReviewIssue] {
        guard showMarks else { return [] }
        if annotationPreview, let transcript = job.record.transcript { return job.record.review.annotations(in: transcript) }
        return job.record.pendingIssues + (job.record.transcript.map { job.record.review.annotations(in: $0) } ?? [])
    }
    var body: some View {
        VStack(spacing: 0) {
            if job.record.phase == .failed || job.record.phase == .cancelled || job.record.phase == .needsConfirmation { recoveryBanner }
            if isReading {
                readingContent
            } else {
                sourceContext
                PairedDocumentView(image: enhanced ? job.enhancedImage : job.sourceImage,
                    transcript: job.record.transcript, issues: visibleIssues,
                    uncertainLineIDs: showUncertainty ? job.uncertainLineIDs : [], wordRegions: job.wordRegions,
                    uncertainWordRects: showUncertainty ? job.uncertainWordRects : [],
                    unlocatedTextRanges: showUncertainty ? job.unlocatedTextRanges : [], selectedIssueID: store.selectedIssueID,
                    aspect: Double(job.record.height) / Double(max(1, job.record.width)), zoom: job.reading.zoom,
                    mode: mode, wipeFraction: wipeFraction,
                    onZoomChange: { job.reading.zoom = $0; store.saveReading(job) },
                    onWipeChange: { wipeFraction = $0 },
                    onLineClick: { id in store.selectedIssueID = visibleIssues.first { $0.lineID == id }?.id },
                    onIssueClick: { store.selectedIssueID = $0 },
                    sourceOnly: presentation == "source", position: CGPoint(x: job.reading.offsetX, y: job.reading.offsetY),
                    onPositionChange: { job.reading.offsetX = $0.x; job.reading.offsetY = $0.y; store.saveReading(job) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            controls
            Divider().overlay(WorkspaceStyle.border)
            HStack(spacing: 12) {
                if job.record.phase == .complete {
                    Text(job.record.reviewStatus).foregroundStyle(.secondary)
                    Divider().frame(height: 12)
                }
                if job.savingReview { ProgressView().controlSize(.mini); Text("正在保存") }
                else if let error = job.reviewSaveError {
                    Label("尚未保存", systemImage: "exclamationmark.circle").foregroundStyle(Color(nsColor: WorkspaceStyle.warningColor)).help(error)
                    Button("重试保存") { store.retryReviewSave(job) }
                } else { Label("已保存", systemImage: "checkmark").foregroundStyle(.secondary) }
                Spacer()
                if job.isReviewed { Button("继续修改") { store.reopenReview(job, undoManager: undoManager) } }
            }.font(.system(size: 12)).buttonStyle(.borderless)
                .padding(.horizontal, WorkspaceGrid.paneInset).frame(height: WorkspaceGrid.footerHeight)
        }
        .background(WorkspaceStyle.canvas)
        .sheet(isPresented: $editing) { TranscriptEditor(store: store, job: job) }
        .onChange(of: job.reading.presentation) { _, _ in store.saveReading(job) }
        .onChange(of: job.reading.zoom) { _, _ in store.saveReading(job) }
        .onChange(of: store.selectedIssueID) { _, id in job.reading.selectedIssueID = id; store.saveReading(job) }
    }
    private var sourceContext: some View {
        GeometryReader { geometry in
            let paneWidth = (geometry.size.width - WorkspaceGrid.documentGap) / 2
            HStack(alignment: .top, spacing: WorkspaceGrid.documentGap) {
                VStack(alignment: .leading, spacing: 0) {
                    Menu {
                        Button("扫描增强") { enhanced = true }
                        Button("原色") { enhanced = false }
                        Divider(); Button("查看完整原照片") { store.showOriginal(job) }
                    } label: {
                        Text("原稿").fontWeight(.medium)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                    .frame(height: WorkspaceGrid.controlHeight)
                    .tint(Color(nsColor: .secondaryLabelColor)).help(enhanced ? "扫描增强" : "原色")
                    // Its fixed second line remains reserved even without a warning.
                    Label("这份作业可读性较差", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).frame(height: 20)
                        .opacity(job.hasPoorReadability ? 1 : 0).accessibilityHidden(!job.hasPoorReadability)
                }.frame(width: presentation == "source" ? geometry.size.width : paneWidth, alignment: .leading)
                if presentation != "source" {
                    HStack(spacing: 8) {
                        Text("识别稿").fontWeight(.medium)
                        Spacer(minLength: 0)
                        Toggle("疑义标记", isOn: $showUncertainty).toggleStyle(.switch).controlSize(.mini)
                            .help("紫色表示读字分歧或缺少可靠定位。")
                        copyButton
                    }.frame(width: paneWidth, height: WorkspaceGrid.controlHeight)
                }
            }
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .padding(.horizontal, WorkspaceGrid.paneInset).padding(.top, 8)
        .frame(height: WorkspaceGrid.contextHeight)
    }
    @AppStorage("comparisonWipeFraction") private var wipeFraction = 0.5
    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(job.record.transcript?.text ?? "", forType: .string)
        } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("复制识别文字").disabled(job.record.transcript == nil)
    }
    private var readingContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button("识别文字") { annotationPreview = false }.fontWeight(annotationPreview ? .regular : .semibold)
                Button("批注预览") { annotationPreview = true }.fontWeight(annotationPreview ? .semibold : .regular)
                Spacer(); copyButton
            }.font(.system(size: 13)).buttonStyle(.plain).foregroundStyle(.secondary)
                .padding(.horizontal, WorkspaceGrid.readingInset).frame(height: WorkspaceGrid.contextHeight)
            Divider().padding(.horizontal, WorkspaceGrid.readingInset)
            ReadingDocumentView(transcript: job.record.transcript, issues: visibleIssues,
                selectedIssueID: store.selectedIssueID, fontSize: fontSize, onSelect: { store.selectedIssueID = $0 },
                review: annotationPreview ? job.record.review : nil,
                uncertainRanges: showUncertainty ? job.unlocatedTextRanges + job.wordRegions.filter { job.uncertainWordRects.contains($0.rect) }.compactMap(\.range) : [],
                offset: job.reading.readingOffsetY,
                onScroll: { job.reading.readingOffsetY = $0; store.saveReading(job) })
        }
    }
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                markControls
                Spacer(minLength: 12)
                processingStatus
                scaleControls
            }.frame(height: 42)
            VStack(spacing: 0) {
                HStack { processingStatus; Spacer(minLength: 0) }.frame(height: 36)
                HStack { markControls; Spacer(minLength: 12); scaleControls }.frame(height: 36)
            }
        }
        .font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.borderless)
        .padding(.horizontal, WorkspaceGrid.paneInset)
    }
    private var markControls: some View {
        HStack(spacing: 12) {
            Toggle("问题标记", isOn: $showMarks).toggleStyle(.checkbox)
            if isReading { Toggle("疑义标记", isOn: $showUncertainty).toggleStyle(.checkbox) }
        }.fixedSize()
    }
    private var processingStatus: some View {
        ProcessingStatusView(store: store, job: job, mode: mode)
    }
    private var scaleControls: some View {
        HStack(spacing: 12) {
            if isReading {
                Button { fontSize = max(14, fontSize - 1) } label: { Image(systemName: "minus") }
                    .help("缩小正文字号").accessibilityLabel("缩小正文字号").disabled(fontSize <= 14)
                Text("\(Int(fontSize)) pt").monospacedDigit()
                Button { fontSize = min(28, fontSize + 1) } label: { Image(systemName: "plus") }
                    .help("放大正文字号").accessibilityLabel("放大正文字号").disabled(fontSize >= 28)
            } else {
                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                Slider(value: $job.reading.zoom, in: 0.75...2).frame(width: 92).accessibilityLabel("对照缩放")
                Button("\(Int(job.reading.zoom * 100))%") { job.reading.zoom = 1 }
                    .monospacedDigit().frame(width: 40).help("恢复 100%")
            }
        }.fixedSize()
    }
    private var recoveryBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Color(nsColor: WorkspaceStyle.warningColor))
            Text(job.record.error ?? (job.record.phase == .cancelled ? "处理已暂停" : "识别结果已保留，可继续审核"))
                .font(.callout).lineLimit(3).textSelection(.enabled)
            Spacer(minLength: 0)
            Button(job.record.phase == .cancelled ? "继续处理" : "重试此阶段") { store.retry(job) }.disabled(store.activeID == job.id)
        }.padding(.horizontal, 22).padding(.vertical, 12).background(Color(nsColor: WorkspaceStyle.warningColor).opacity(0.06))
    }
}

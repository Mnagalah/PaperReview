import SwiftUI
import PaperReviewCore

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @State private var dropping = false
    @State private var deletingJob: Assignment?
    @State private var search = ""
    @State private var filter: AssignmentFilter = .all
    @State private var completing = false
    @State private var editing = false
    @State private var inspectorProcessed = false

    private var filtered: [Assignment] {
        store.assignments.filter { filter.includes($0) && (search.isEmpty || $0.record.displayFilename.localizedCaseInsensitiveContains(search)) }
    }
    private var workspaceTitle: String {
        store.selected.map { "作业批改 — \($0.record.displayFilename)" } ?? "作业批改"
    }
    var body: some View {
        GeometryReader { geometry in
            WorkspaceSplitView(width: geometry.size.width, toolbarState: toolbarState) {
                assignmentList(inPicker: false)
            } document: {
                workspace.frame(minWidth: WorkspaceLayout.documentMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
            } inspector: {
                ReviewInspector(store: store, job: store.selected, processed: $inspectorProcessed)
            } picker: {
                assignmentList(inPicker: true).frame(width: 260, height: 520)
            }
            .environment(\.workspaceSize, geometry.size)
            .focusedSceneValue(\.workspaceActions, WorkspaceCommandActions(
                completionTitle: completionTitle, canComplete: canComplete, complete: completeReview))
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(workspaceTitle)
        .onChange(of: store.selectedID) { _, _ in
            inspectorProcessed = store.selected?.record.review.confirmed.contains { $0.issue.id == store.selectedIssueID } == true
        }
        .onChange(of: store.selectedIssueID) { _, id in
            if let id, let job = store.selected {
                if job.record.pendingIssues.contains(where: { $0.id == id }) { inspectorProcessed = false }
                else if job.record.review.confirmed.contains(where: { $0.issue.id == id }) { inspectorProcessed = true }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.filter { ["jpg", "jpeg", "png", "heic", "tif", "tiff"].contains($0.pathExtension.lowercased()) }
            guard !images.isEmpty else { return false }
            Task { await store.importURLs(images) }; return true
        } isTargeted: { dropping = $0 }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 14).stroke(.tint, lineWidth: 2).padding(12).allowsHitTesting(false) } }
        .alert("需要处理", isPresented: Binding(get: { store.globalError != nil }, set: { if !$0 { store.globalError = nil } })) {
            Button("好") { store.globalError = nil }
        } message: { Text(store.globalError ?? "") }
        .alert("完成这份批阅？", isPresented: $completing) {
            Button("继续批阅", role: .cancel) {}
            Button("放弃余下 \(store.selected?.record.pendingIssues.count ?? 0) 条并完成") {
                if let job = store.selected { store.completeReview(job, keepRemaining: true, undoManager: undoManager) }
            }
        } message: { Text("还有未确认的建议。") }
        .alert("删除作业？", isPresented: Binding(get: { deletingJob != nil }, set: { if !$0 { deletingJob = nil } }), presenting: deletingJob) { job in
            Button("移到废纸篓", role: .destructive) { deletingJob = nil; Task { await store.trash(job) } }
            Button("取消", role: .cancel) { deletingJob = nil }
        } message: { job in Text("“\(job.record.title)”将移到废纸篓，原照片保留。") }
        .sheet(isPresented: Binding(get: { !store.duplicatePhotos.isEmpty }, set: { if !$0 { store.duplicatePhotos = [] } })) { ImportDuplicatesView(store: store) }
    }
    private var toolbarState: WorkspaceToolbarState {
        WorkspaceToolbarState(filename: store.selected?.record.displayFilename ?? "作文批阅",
            selectedID: store.selectedID, completionTitle: completionTitle, canComplete: canComplete,
            canExport: store.selected?.record.transcript != nil,
            canEdit: store.selected.map { $0.record.transcript != nil && store.activeID != $0.id && !$0.savingReview } ?? false,
            canWipe: store.selected?.record.transcript?.isAligned == true,
            reviewIsSaving: store.selected?.savingReview == true,
            presentation: store.selected?.reading.presentation ?? "sideBySide",
            editorTitle: store.selected?.hasPoorReadability == true ? "核对原文" : "校对识别稿",
            importPhoto: { store.importPanel() },
            export: { annotated in if let job = store.selected { store.export(job, annotated: annotated) } },
            complete: completeReview, edit: { editing = true },
            selectPresentation: { value in if let job = store.selected { job.reading.presentation = value; store.saveReading(job) } },
            canReview: store.selected.map { $0.record.transcript != nil && !$0.record.phase.isRunning
                && store.activeID != $0.id && !$0.savingReview && $0.reviewSaveError == nil } ?? false,
            review: { if let job = store.selected { store.retry(job) } })
    }
    private var completionTitle: String { store.selected?.isReviewed == true ? "下一份" : "完成批阅" }
    private var canComplete: Bool {
        guard let job = store.selected else { return false }
        return job.record.phase == .complete && !job.savingReview && job.reviewSaveError == nil
            && store.activeID != job.id
            && (!job.isReviewed || store.assignments.contains { !$0.isReviewed && $0.id != job.id })
    }
    private func completeReview() {
        guard canComplete, let job = store.selected else { return }
        if job.isReviewed { store.selectNextPending() }
        else if job.record.pendingIssues.isEmpty { store.completeReview(job, undoManager: undoManager) }
        else { completing = true }
    }
    private func assignmentList(inPicker: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if inPicker {
                Button { store.importPanel() } label: { Label("导入照片", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large).padding(.horizontal, 14).padding(.top, 16)
            }
            TextField("搜索作业", text: $search).textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14).frame(height: WorkspaceGrid.contextHeight).accessibilityLabel("搜索作业")
            VStack(spacing: 3) {
                ForEach(AssignmentFilter.allCases) { item in
                    Button { filter = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).frame(width: 18)
                            Text(item.title)
                            Spacer()
                            Text("\(store.assignments.filter { item.includes($0) }.count)").font(.caption).monospacedDigit()
                        }.font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                            .foregroundStyle(filter == item ? .primary : .secondary)
                            .background(filter == item ? WorkspaceStyle.selection.opacity(0.55) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }.padding(.horizontal, 12).padding(.bottom, 22)
            List(selection: Binding(get: { store.selectedID }, set: { if let id = $0 { store.select(id) } })) {
                ForEach(filtered) { job in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text").font(.system(size: 17))
                            .frame(width: 19, height: 19).foregroundStyle(.secondary).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job.record.displayFilename).font(.system(size: 13, weight: .medium))
                                .lineLimit(1).truncationMode(.middle).help(job.record.displayFilename)
                            Text(job.isReviewed ? "已批阅" : job.record.phase == .complete ? "\(job.record.pendingIssues.count) 个问题待确认" : job.record.phase.title)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8).tag(job.id)
                    .contextMenu { Button("删除作业…", role: .destructive) { deletingJob = job }.disabled(!store.canDelete(job) || job.savingReview) }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                .overlay { if filtered.isEmpty { Text(search.isEmpty ? "暂无作业" : "没有匹配的作业").font(.callout).foregroundStyle(.secondary) } }
                .onDeleteCommand { if let job = store.selected, store.canDelete(job), !job.savingReview { deletingJob = job } }
            Button { openSettings() } label: {
                HStack(spacing: 8) {
                    Circle().fill(store.allModelsReady ? Color.green.opacity(0.7) : Color.secondary).frame(width: 5, height: 5)
                    Text(store.allModelsReady ? "本机服务已就绪" : "本机服务未就绪")
                    Spacer(); Image(systemName: "chevron.right").font(.caption2)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: WorkspaceGrid.footerHeight)
            }.buttonStyle(.plain)
        }
    }
    private var workspace: some View {
        Group {
            if let job = store.selected { ComparisonView(store: store, job: job, editing: $editing).id(job.id) }
            else {
                VStack(spacing: 18) {
                    Image(systemName: "doc.text.viewfinder").font(.system(size: 42, weight: .light)).foregroundStyle(.secondary)
                    Text("导入作文照片").font(.title2.weight(.semibold))
                    Text("将照片拖到这里，或按 ⌘O").font(.callout).foregroundStyle(.secondary)
                    Button("导入照片…") { store.importPanel() }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(WorkspaceStyle.canvas)
    }
}

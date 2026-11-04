import SwiftUI
import PaperReviewCore

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    @State private var dropping = false
    @State private var deletingJob: Assignment?
    @SceneStorage("workspaceSidebarVisible") private var showingSidebar = true

    var body: some View {
        HSplitView {
            if showingSidebar { sidebar.frame(minWidth: 190, idealWidth: 225, maxWidth: 280) }
            workspace.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            if store.showingInspector {
                ReviewInspector(store: store, job: store.selected)
                    .frame(minWidth: 280, idealWidth: 315, maxWidth: 390, maxHeight: .infinity)
            }
        }
        .background(WorkspaceStyle.canvas)
        .navigationTitle(store.selected.map { "作业批改 — \($0.record.displayFilename)" } ?? "作业批改")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showingSidebar.toggle() } label: { Label("作业列表", systemImage: "sidebar.left") }
                    .help(showingSidebar ? "隐藏作业列表" : "显示作业列表")
                    .keyboardShortcut("s", modifiers: [.command, .option])
            }
            ToolbarItem {
                Menu {
                    Button("忠实原文（Markdown）…") { if let job = store.selected { store.export(job, annotated: false) } }
                    Button("原文与批注（Markdown）…") { if let job = store.selected { store.export(job, annotated: true) } }
                } label: { Label("导出", systemImage: "square.and.arrow.up") }
                .disabled(store.selected?.record.transcript == nil)
            }
            ToolbarItem { SettingsLink { Label("模型设置", systemImage: "gearshape") } }
            ToolbarItem {
                Button { store.showingInspector.toggle() } label: { Label("基础审核", systemImage: "sidebar.right") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.filter { ["jpg", "jpeg", "png", "heic", "tif", "tiff"].contains($0.pathExtension.lowercased()) }
            guard !images.isEmpty else { return false }
            Task { await store.importURLs(images) }; return true
        } isTargeted: { dropping = $0 }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 10).stroke(.tint, lineWidth: 3).padding(8).allowsHitTesting(false) } }
        .alert("需要处理", isPresented: Binding(get: { store.globalError != nil }, set: { if !$0 { store.globalError = nil } })) {
            Button("好") { store.globalError = nil }
        } message: { Text(store.globalError ?? "") }
        .alert("删除作业？", isPresented: Binding(get: { deletingJob != nil }, set: { if !$0 { deletingJob = nil } }), presenting: deletingJob) { job in
            Button("移到废纸篓", role: .destructive) { deletingJob = nil; Task { await store.trash(job) } }
            Button("取消", role: .cancel) { deletingJob = nil }
        } message: { job in
            Text("将“\(job.record.title)”的本机作业副本移到废纸篓。导入来源照片不变。")
        }
        .sheet(isPresented: Binding(get: { !store.duplicatePhotos.isEmpty }, set: { if !$0 { store.duplicatePhotos = [] } })) {
            ImportDuplicatesView(store: store)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("作业").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(store.assignments.count)").font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
            }.padding(.horizontal, 18).frame(height: 60)
            Divider()
            Button { store.importPanel() } label: {
                Label("导入照片…", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered).controlSize(.large).help("导入作文照片（⌘O）")
                .padding(.horizontal, 14).frame(height: 52)
            List(selection: Binding(get: { store.selectedID }, set: { store.select($0) })) {
                ForEach(store.assignments) { job in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.record.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Text(job.record.phase.title).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "doc.text").foregroundStyle(.secondary) }
                        .tag(job.id).padding(.vertical, 6)
                        .listRowBackground(store.selectedID == job.id ? WorkspaceStyle.selection : Color.clear)
                        .contextMenu {
                            Button("删除作业…", role: .destructive) { deletingJob = job }.disabled(!store.canDelete(job))
                        }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                .onDeleteCommand { if let job = store.selected, store.canDelete(job) { deletingJob = job } }
            Divider()
            Button { openSettings() } label: {
                Label(store.allModelsReady ? "模型已就绪" : "启动模型", systemImage: store.allModelsReady ? "checkmark.circle" : "externaldrive")
                    .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 40)
        }.background(WorkspaceStyle.sidebar)
    }

    private var workspace: some View {
        Group {
            if let job = store.selected { ComparisonView(store: store, job: job) }
            else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.viewfinder").font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
                    Text("导入作文照片").font(.title2.weight(.semibold))
                    Text("将照片拖到这里").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(WorkspaceStyle.canvas)
    }
}

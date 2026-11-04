import SwiftUI
import PaperReviewCore

struct ModelSettingsView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var controller: ModelProcessController
    @State private var draft: ModelConfiguration
    @State private var advanced = false
    @State private var confirmingDownload = false
    @AppStorage(WorkspaceAppearance.preferenceKey) private var appearance = WorkspaceAppearance.dark.rawValue
    init(store: WorkspaceStore, controller: ModelProcessController) {
        self.store = store; self.controller = controller
        _draft = State(initialValue: store.configuration)
    }
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    ForEach(WorkspaceAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented)
            }
            Section("本机模型") {
                status("MiniCPM-OCR", ready: store.modelHealth[0])
                status("Jev", ready: store.modelHealth[1])
                status("MiniCPM5-2B", ready: store.modelHealth[2])
                HStack {
                    Button("下载模型") { confirmingDownload = true }
                    Button("启动模型") { controller.run("start_models.sh", store: store) }
                    Button("停止模型") { controller.run("stop_models.sh", store: store) }
                    Spacer()
                    Button("删除模型…", role: .destructive) { controller.prepareRemoval() }
                    if controller.busy && !controller.isDownloadActive { ProgressView().controlSize(.small) }
                    Button { Task { await store.checkModels() } } label: { Image(systemName: "arrow.clockwise") }.help("检查连接")
                }.disabled(controller.busy || store.activeID != nil)
                if let progress = controller.download {
                    ModelDownloadView(progress: progress,
                        retry: { controller.run("setup_models_modelscope.sh", store: store) },
                        pause: { controller.pauseDownload() },
                        retryDisabled: controller.busy || store.activeID != nil)
                }
                if !controller.output.isEmpty && controller.showsCommandOutput {
                    Text(controller.output).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                SettingsDisclosure(title: "高级设置", isExpanded: $advanced) {
                    ModelAdvancedSettingsView(store: store, controller: controller, draft: $draft)
                }
            }
            Text("作业只在本机处理。模型独立运行，关闭窗口后可在此停止。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).padding(10).frame(width: 640, height: 720)
        .alert("删除本机模型？", isPresented: Binding(get: { controller.removal != nil }, set: { if !$0 { controller.removal = nil } }),
            presenting: controller.removal) { plan in
            Button("移到废纸篓", role: .destructive) { controller.removeModels(plan) }
            Button("取消", role: .cancel) {}
        } message: { plan in
            Text("将 \(ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .decimal)) 模型及未完成下载移到废纸篓。运行时和学生作业保留。\n\(plan.home.path)")
        }
        .alert("下载本机模型？", isPresented: $confirmingDownload) {
            Button("下载") { controller.run("setup_models_modelscope.sh", store: store) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("从 OpenBMB 官方仓库下载模型、从 llama.cpp 官方发布页下载运行时，合计约 5.94 GB。支持续传，已有完整文件会跳过。\n保存到：\(controller.modelHome)")
        }
        .task { await store.checkModels() }
    }
    private func status(_ name: String, ready: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            Label(ready ? "已就绪" : "未启动", systemImage: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? Color.green : Color.secondary)
        }
    }
}

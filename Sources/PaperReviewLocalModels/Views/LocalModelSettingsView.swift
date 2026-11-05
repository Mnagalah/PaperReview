import SwiftUI
import PaperReviewCore

public struct LocalModelSettingsView: View {
    @Bindable private var module: LocalModelModule
    private let isProcessing: Bool
    private var controller: ModelProcessController { module.controller }
    @State private var draft: ModelConfiguration
    @State private var advanced = false
    @State private var confirmingDownload = false
    public init(module: LocalModelModule, isProcessing: Bool) {
        self.module = module; self.isProcessing = isProcessing
        _draft = State(initialValue: module.configuration)
    }
    public var body: some View {
        Group {
            Section("本机模型") {
                status("MiniCPM-OCR", ready: module.readiness.isReady(.ocr))
                status("Jev", ready: module.readiness.isReady(.jev))
                status("MiniCPM5-2B", ready: module.readiness.isReady(.review))
                HStack {
                    Button("下载模型") { confirmingDownload = true }
                    Button("启动模型") { module.run(.start) }
                    Button("停止模型") { module.run(.stop) }
                    Spacer()
                    Button("删除模型…", role: .destructive) { controller.prepareRemoval() }
                    if controller.busy && !controller.isDownloadActive { ProgressView().controlSize(.small) }
                    Button { Task { await module.checkReadiness() } } label: { Image(systemName: "arrow.clockwise") }.help("检查连接")
                }.disabled(controller.busy || isProcessing)
                if let progress = controller.download {
                    ModelDownloadView(progress: progress,
                        retry: { module.run(.download) },
                        pause: { controller.pauseDownload() },
                        retryDisabled: controller.busy || isProcessing)
                }
                if !controller.output.isEmpty && controller.showsCommandOutput {
                    Text(controller.output).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                SettingsDisclosure(title: "高级设置", isExpanded: $advanced) {
                    ModelAdvancedSettingsView(module: module, isProcessing: isProcessing, draft: $draft)
                }
            }
            Text("作业只在本机处理。模型独立运行，关闭窗口后可在此停止。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .alert("删除本机模型？", isPresented: Binding(get: { controller.removal != nil }, set: { if !$0 { controller.removal = nil } }),
            presenting: controller.removal) { plan in
            Button("移到废纸篓", role: .destructive) { controller.removeModels(plan) }
            Button("取消", role: .cancel) {}
        } message: { plan in
            Text("将 \(ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .decimal)) 模型及未完成下载移到废纸篓。运行时和学生作业保留。\n\(plan.home.path)")
        }
        .alert("下载本机模型？", isPresented: $confirmingDownload) {
            Button("下载") { module.run(.download) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("从 OpenBMB 官方仓库下载模型、从 llama.cpp 官方发布页下载运行时，合计约 5.94 GB。支持续传，已有完整文件会跳过。\n保存到：\(controller.modelHome)")
        }
        .task { await module.checkReadiness() }
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

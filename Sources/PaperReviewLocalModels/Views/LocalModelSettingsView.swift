import SwiftUI
import PaperReviewCore

public enum LocalModelSettingsSection { case all, services, advanced }

public struct LocalModelSettingsView: View {
    @Bindable private var module: LocalModelModule
    private let isProcessing: Bool
    private let section: LocalModelSettingsSection
    private var controller: ModelProcessController { module.controller }
    @State private var draft: ModelConfiguration
    @State private var advanced = false
    @State private var confirmingDownload = false
    @State private var installed: [String: String] = [:]
    public init(module: LocalModelModule, isProcessing: Bool, section: LocalModelSettingsSection = .all) {
        self.module = module; self.isProcessing = isProcessing; self.section = section
        _draft = State(initialValue: module.configuration)
    }
    public var body: some View {
        Group {
            if section != .advanced { serviceSettings }
            if section != .services {
                Section("连接与识别参数") {
                    if section == .advanced {
                        ModelAdvancedSettingsView(module: module, isProcessing: isProcessing, draft: $draft)
                    } else {
                        SettingsDisclosure(title: "高级设置", isExpanded: $advanced) {
                            ModelAdvancedSettingsView(module: module, isProcessing: isProcessing, draft: $draft)
                        }
                    }
                }
            }
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
        .task { await module.checkReadiness(); installed = controller.installationStatuses() }
        .onChange(of: controller.busy) { _, busy in if !busy { installed = controller.installationStatuses() } }
    }
    private var serviceSettings: some View {
        Group {
            Section {
                status("MiniCPM-OCR", id: "ocr", role: .ocr)
                status("Jev", id: "jev", role: .jev)
                status("MiniCPM5-2B", id: "review", role: .review)
                HStack {
                    Button("下载全部模型") { confirmingDownload = true }
                    Button("启动全部") { module.run(.start) }
                    Button("停止全部") { module.run(.stop) }
                    Spacer()
                    if controller.busy && !controller.isDownloadActive { ProgressView().controlSize(.small) }
                    Button { Task { await module.checkReadiness(); installed = controller.installationStatuses() } }
                        label: { Image(systemName: "arrow.clockwise") }.help("检查连接")
                }.disabled(controller.busy || isProcessing)
                if let progress = controller.download {
                    ModelDownloadView(progress: progress, retry: { module.run(.download) },
                        pause: { controller.pauseDownload() }, retryDisabled: controller.busy || isProcessing)
                }
                if !controller.output.isEmpty && controller.showsCommandOutput {
                    Text(controller.output).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("本机模型") }
            Section("存储") {
                HStack {
                    Text("本机模型文件")
                    Spacer()
                    Button("删除全部模型…", role: .destructive) { controller.prepareRemoval() }
                        .disabled(controller.busy || isProcessing)
                }
            }
        }
    }
    private func status(_ name: String, id: String, role: ModelRole) -> some View {
        let ready = module.readiness.isReady(role)
        return HStack {
            Text(name)
            Spacer()
            Label(ready ? "已就绪" : installed[id] ?? "未就绪", systemImage: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? Color.green : Color.secondary)
        }
    }
}

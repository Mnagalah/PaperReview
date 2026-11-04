import SwiftUI
import PaperReviewCore

struct ModelSettingsView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var controller: ModelProcessController
    @State private var draft: ModelConfiguration
    @State private var message = ""
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
                    if controller.busy { ProgressView().controlSize(.small) }
                    Button { Task { await store.checkModels() } } label: { Image(systemName: "arrow.clockwise") }.help("检查连接")
                }.disabled(controller.busy || store.activeID != nil)
                if !controller.output.isEmpty {
                    Text(controller.output).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                DisclosureGroup("高级设置", isExpanded: $advanced) {
                    TextField("OCR 地址", text: $draft.ocrURL)
                    TextField("Jev 地址", text: $draft.jevURL)
                    TextField("审核地址", text: $draft.reviewURL)
                    TextField("模型目录", text: $controller.modelHome).disabled(controller.busy)
                    HStack {
                        Text("复识参考分")
                        Slider(value: $draft.threshold, in: 0.1...0.999, step: 0.01).frame(width: 150)
                        Text(draft.threshold, format: .number.precision(.fractionLength(2))).monospacedDigit()
                    }
                    Stepper("最多识别 \(draft.maximumAttempts) 次", value: $draft.maximumAttempts, in: 1...3)
                    Text("逐词核验稳定时继续审核；其余低分结果追加候选。分数不是识别准确率。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("保存") {
                        do { try store.saveConfiguration(draft); message = "已保存"; Task { await store.checkModels() } }
                        catch { message = error.localizedDescription }
                    }
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
            }
            Text("作业只在本机处理。模型独立运行，关闭窗口后可在此停止。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).padding(10).frame(width: 610, height: 640)
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

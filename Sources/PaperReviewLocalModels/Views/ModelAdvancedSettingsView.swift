import SwiftUI
import AppKit
import PaperReviewCore

struct ModelAdvancedSettingsView: View {
    @Bindable var module: LocalModelModule
    let isProcessing: Bool
    private var controller: ModelProcessController { module.controller }
    @Binding var draft: ModelConfiguration
    @State private var message = ""
    @State private var failed = false
    @State private var directoryPanel: NSOpenPanel?
    var body: some View {
        VStack(spacing: 12) {
            row("OCR 地址") { endpoint("OCR 地址", value: $draft.ocrURL) }
            row("Jev 地址") { endpoint("Jev 地址", value: $draft.jevURL) }
            row("审核地址") { endpoint("审核地址", value: $draft.reviewURL) }
            row("模型目录") {
                HStack(spacing: 8) {
                    TextField("完整路径", text: Binding(get: { controller.modelHome }, set: { controller.modelHome = $0 }))
                        .textFieldStyle(.roundedBorder).accessibilityLabel("模型目录")
                        .help(controller.modelHome)
                    Button("选择…", action: chooseDirectory)
                }
            }
            Divider().padding(.vertical, 4)
            row("复识参考分") {
                HStack(spacing: 12) {
                    Slider(value: $draft.threshold, in: 0.1...0.999, step: 0.01)
                        .accessibilityLabel("复识参考分")
                    Text(draft.threshold, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                .help("逐词核验稳定时继续审核；其余低分结果追加候选。分数不是识别准确率。")
            }
            row("最多识别") {
                Picker("最多识别", selection: $draft.maximumAttempts) {
                    ForEach(1...3, id: \.self) { Text("\($0) 次").tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 210)
            }
            HStack {
                Text(message).font(.callout).foregroundStyle(failed ? .red : .secondary)
                Spacer()
                Button("保存设置", action: save)
            }.padding(.top, 4)
        }
        .padding(.top, 12)
        .labelsHidden()
        .multilineTextAlignment(.leading)
        .disabled(controller.busy || isProcessing)
        .onChange(of: draft) { _, _ in message = "" }
        .onChange(of: controller.modelHome) { _, _ in message = "" }
    }
    private func endpoint(_ label: String, value: Binding<String>) -> some View {
        TextField("http://127.0.0.1:端口", text: value)
            .textFieldStyle(.roundedBorder).accessibilityLabel(label)
            .onSubmit(save)
    }
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 84, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func save() {
        do {
            try draft.validate()
            try controller.saveModelHome()
            try module.saveConfiguration(draft)
            failed = false; message = "已保存"
            Task { await module.checkReadiness() }
        } catch { failed = true; message = error.localizedDescription }
    }
    private func chooseDirectory() {
        if let directoryPanel { directoryPanel.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = "选择模型目录"; panel.prompt = "选择"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: controller.modelHome)
        directoryPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { controller.modelHome = url.path }
            directoryPanel = nil
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}

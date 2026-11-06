import SwiftUI

struct TranscriptEditor: View {
    let store: WorkspaceStore
    let job: Assignment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workspaceSize) private var workspaceSize
    @State private var text: String
    init(store: WorkspaceStore, job: Assignment) {
        self.store = store; self.job = job
        _text = State(initialValue: job.record.transcript?.text ?? "")
    }
    var body: some View {
        let layout = TranscriptEditorLayout(availableSize: workspaceSize)
        VStack(alignment: .leading, spacing: 16) {
            Text("校对识别稿").font(.title2.weight(.semibold))
            Text("仅修改识别文字，保留学生原有的拼写、语法和标点。")
                .font(.callout).foregroundStyle(.secondary)
            Group {
                if layout.sideBySide {
                    HSplitView {
                        if job.enhancedImage != nil { source.frame(minWidth: 260, idealWidth: 360) }
                        editor.frame(minWidth: 320)
                    }
                } else {
                    VSplitView {
                        if job.enhancedImage != nil { source.frame(minHeight: 100, idealHeight: 150) }
                        editor.frame(minHeight: 160)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text("保存后重新审核，已有批注保留。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).fixedSize()
                Button("保存并审核") { store.confirmTranscript(job, text: text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fixedSize()
            }
        }.padding(24).frame(width: layout.size.width, height: layout.size.height)
    }
    private var editor: some View {
        TextEditor(text: $text).font(.system(size: 16, design: .monospaced)).padding(6)
            .accessibilityLabel("识别结果 Markdown")
    }
    private var source: some View {
        GeometryReader { geometry in
            ScrollView {
                if let image = job.enhancedImage {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: geometry.size.width)
                }
            }.accessibilityLabel("校对原稿")
        }
    }
}

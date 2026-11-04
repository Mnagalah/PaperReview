import SwiftUI

struct TranscriptEditor: View {
    let store: WorkspaceStore
    let job: Assignment
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    init(store: WorkspaceStore, job: Assignment) {
        self.store = store; self.job = job
        _text = State(initialValue: job.record.transcript?.text ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑识别文字").font(.title2.weight(.semibold))
            Text("仅修改识别文字，保留学生原有的拼写、语法和标点。")
                .font(.callout).foregroundStyle(.secondary)
            HSplitView {
                if let image = job.enhancedImage {
                    ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(width: 400) }
                        .frame(minWidth: 280)
                }
                TextEditor(text: $text).font(.system(size: 16, design: .monospaced)).padding(6).frame(minWidth: 400)
                    .accessibilityLabel("忠实原文 Markdown")
            }
            HStack {
                Text("保存后重新审核。") .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存并审核") { store.confirmTranscript(job, text: text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 940, height: 650)
    }
}

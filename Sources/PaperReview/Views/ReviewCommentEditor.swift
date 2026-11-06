import SwiftUI

struct ReviewCommentEditor: View {
    let store: WorkspaceStore
    let job: Assignment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var text: String
    init(store: WorkspaceStore, job: Assignment) {
        self.store = store; self.job = job
        _text = State(initialValue: job.record.review.comment)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("作文评语").font(.title3.weight(.semibold))
            TextEditor(text: $text).font(.body).frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator)).accessibilityLabel("作文评语")
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存评语") { store.saveComment(text, job: job, undoManager: undoManager); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(WorkspacePrimaryButtonStyle())
            }
        }.padding(24).frame(width: 480, height: 300)
    }
}

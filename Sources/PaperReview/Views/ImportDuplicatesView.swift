import SwiftUI

struct ImportDuplicatesView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.duplicatePhotos.count == 1 ? "这张照片已导入" : "\(store.duplicatePhotos.count) 张照片已导入")
                .font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.duplicatePhotos) { duplicate in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(duplicate.url.lastPathComponent).lineLimit(2)
                                Text("已有作业：\(duplicate.existingTitle)").foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button("查看") { store.showExisting(duplicate) }
                                .disabled(!store.assignments.contains { $0.id == duplicate.existingID })
                        }
                    }
                }
            }.frame(maxHeight: 230)
            HStack {
                Button("仍然导入") { store.importDuplicates() }
                Spacer()
                Button("不重复导入") { store.duplicatePhotos = [] }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 460)
    }
}

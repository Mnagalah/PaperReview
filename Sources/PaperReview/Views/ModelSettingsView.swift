import SwiftUI

struct ModelSettingsView<ModelSettings: View>: View {
    @AppStorage(WorkspaceAppearance.preferenceKey) private var appearance = WorkspaceAppearance.dark.rawValue
    @ViewBuilder let modelSettings: () -> ModelSettings
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    ForEach(WorkspaceAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented)
            }
            modelSettings()
        }
        .formStyle(.grouped).padding(10).frame(width: 640, height: 720)
    }
}

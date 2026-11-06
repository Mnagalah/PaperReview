import SwiftUI

struct ModelSettingsView<Services: View, Advanced: View>: View {
    @AppStorage(WorkspaceAppearance.preferenceKey) private var appearance = WorkspaceAppearance.dark.rawValue
    @AppStorage("showProblemMarks") private var showMarks = true
    @AppStorage("showRecognitionUncertainty") private var showUncertainty = false
    @AppStorage("readingFontSize") private var fontSize = 18.0
    @State private var selection = "general"
    @ViewBuilder let services: () -> Services
    @ViewBuilder let advanced: () -> Advanced
    var body: some View {
        TabView(selection: $selection) {
            Form {
                Section("外观") {
                    Picker("主题", selection: $appearance) {
                        ForEach(WorkspaceAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                }
            }.formStyle(.grouped).tabItem { Label("通用", systemImage: "gearshape") }.tag("general")
            Form {
                Section("普通阅读") {
                    HStack {
                        Text("正文字号")
                        Slider(value: $fontSize, in: 14...28, step: 1).accessibilityLabel("普通阅读正文字号")
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44)
                    }
                }
                Section("批阅标记") {
                    Toggle("显示问题标记", isOn: $showMarks)
                    Toggle("显示识别疑义", isOn: $showUncertainty)
                        .help("紫色点线表示读字分歧或缺少可靠定位，不表示语言错误。")
                }
            }.formStyle(.grouped).tabItem { Label("阅读与批阅", systemImage: "text.book.closed") }.tag("reading")
            Form { services() }.formStyle(.grouped).tabItem { Label("本地服务", systemImage: "externaldrive") }.tag("services")
            Form { advanced() }.formStyle(.grouped).tabItem { Label("高级", systemImage: "slider.horizontal.3") }.tag("advanced")
        }.padding(16).frame(width: 680, height: selection == "general" ? 200 : selection == "reading" ? 300 : selection == "advanced" ? 440 : 520)
    }
}

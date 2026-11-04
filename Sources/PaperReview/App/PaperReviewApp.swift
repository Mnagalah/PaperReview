import SwiftUI
import AppKit

@main struct PaperReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WorkspaceStore()
    @State private var models = ModelProcessController()
    @AppStorage(WorkspaceAppearance.preferenceKey) private var appearance = WorkspaceAppearance.dark.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1120, minHeight: 680)
                .preferredColorScheme((WorkspaceAppearance(rawValue: appearance) ?? .dark).colorScheme)
                .tint(WorkspaceStyle.action)
                .accentColor(WorkspaceStyle.action)
                .task { await store.restore() }
        }
        .defaultSize(width: 1480, height: 920)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入作文照片…") { store.importPanel() }.keyboardShortcut("o")
            }
            CommandMenu("作业") {
                Button("导出忠实原文…") { if let job = store.selected { store.export(job, annotated: false) } }
                    .disabled(store.selected?.record.transcript == nil)
                Button("导出原文与批注…") { if let job = store.selected { store.export(job, annotated: true) } }
                    .disabled(store.selected?.record.transcript == nil)
                Divider()
                Button("暂停处理") { store.cancel() }.disabled(store.activeID == nil)
            }
        }
        Settings {
            ModelSettingsView(store: store, controller: models)
                .preferredColorScheme((WorkspaceAppearance(rawValue: appearance) ?? .dark).colorScheme)
                .tint(WorkspaceStyle.action)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

import SwiftUI
import AppKit
import PaperReviewCore
import PaperReviewLocalModels

@main struct PaperReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: WorkspaceStore
    @State private var models: LocalModelModule
    @AppStorage(WorkspaceAppearance.preferenceKey) private var appearance = WorkspaceAppearance.dark.rawValue
    init() {
        let controller = LocalModelModule()
        _models = State(initialValue: controller)
        let workspace = WorkspaceStore(models: controller)
        _store = State(initialValue: workspace)
        delegate.models = controller
        delegate.store = workspace
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: WorkspaceLayout.minimumWidth, minHeight: WorkspaceLayout.minimumHeight)
                .preferredColorScheme((WorkspaceAppearance(rawValue: appearance) ?? .dark).colorScheme)
                .tint(WorkspaceStyle.action)
                .accentColor(WorkspaceStyle.action)
                .task { await store.restore() }
        }
        .defaultSize(width: 1480, height: 920)
        // Keep the system titlebar's drag/double-click behavior. AppKit hides
        // only its title text when installing the column-aligned toolbar.
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            WorkspaceCommands()
            CommandGroup(replacing: .newItem) {
                Button("导入作文照片…") { store.importPanel() }.keyboardShortcut("o")
            }
            CommandMenu("作业") {
                Button("导出识别结果…") { if let job = store.selected { store.export(job, annotated: false) } }
                    .disabled(store.selected?.record.transcript == nil)
                Button("导出识别结果（含批注）…") { if let job = store.selected { store.export(job, annotated: true) } }
                    .disabled(store.selected?.record.transcript == nil)
                Divider()
                Button("暂停处理") { store.cancel() }.disabled(store.activeID == nil)
            }
        }
        Settings {
            ModelSettingsView {
                LocalModelSettingsView(module: models, isProcessing: store.activeID != nil, section: .services)
            } advanced: {
                LocalModelSettingsView(module: models, isProcessing: store.activeID != nil, section: .advanced)
            }
                .preferredColorScheme((WorkspaceAppearance(rawValue: appearance) ?? .dark).colorScheme)
                .tint(WorkspaceStyle.action)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var models: (any ModelModule)?
    weak var store: WorkspaceStore?
    private var waitingForDownload = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let store, store.assignments.contains(where: { $0.reviewSaveError != nil }) {
            let alert = NSAlert()
            alert.messageText = "批阅修改尚未保存"
            alert.informativeText = "请先返回作业重试保存，再退出。"
            alert.addButton(withTitle: "返回作业")
            alert.runModal()
            return .terminateCancel
        }
        guard models?.needsTerminationPreparation == true || store?.hasReviewWrites == true || store?.hasReadingWrites == true else { return .terminateNow }
        guard !waitingForDownload else { return .terminateLater }
        waitingForDownload = true
        Task {
            await store?.finishReviewWrites()
            await store?.finishReadingWrites()
            await models?.prepareForTermination()
            if store?.assignments.contains(where: { $0.reviewSaveError != nil }) == true {
                waitingForDownload = false
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

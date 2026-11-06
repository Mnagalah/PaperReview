import SwiftUI

/// The focused workspace owns these actions, including its completion alert.
/// Menu and toolbar paths therefore share both validation and confirmation.
struct WorkspaceCommandActions {
    let completionTitle: String
    let canComplete: Bool
    let complete: () -> Void
}

private struct WorkspaceCommandKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

extension FocusedValues {
    var workspaceActions: WorkspaceCommandActions? {
        get { self[WorkspaceCommandKey.self] }
        set { self[WorkspaceCommandKey.self] = newValue }
    }
}

struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceActions) private var actions
    var body: some Commands {
        CommandGroup(replacing: .sidebar) {}
        CommandMenu("批阅") {
            Button(actions?.completionTitle ?? "完成批阅") { actions?.complete() }
                .keyboardShortcut(.return, modifiers: .command).disabled(actions?.canComplete != true)
        }
    }
}

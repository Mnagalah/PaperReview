import AppKit
import SwiftUI
import Testing
@testable import PaperReview

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_UI_TOOLBAR"] == "1"))
@MainActor func nativeViewModesKeepTheirVisibleWidthAfterCompactRoundTrip() async throws {
    var selections: [String] = []
    var state = WorkspaceToolbarState(filename: "工具栏交互夹具.png", selectedID: UUID(), completionTitle: "完成批阅",
        canComplete: true, canExport: true, canEdit: true, canWipe: true, reviewIsSaving: false,
        presentation: "sideBySide", editorTitle: "校对识别稿", importPhoto: {}, export: { _ in },
        complete: {}, edit: {}, selectPresentation: { selections.append($0) })
    let controller = WorkspaceSplitController(sidebar: AnyView(Text("来源").frame(maxWidth: .infinity, maxHeight: .infinity)),
        document: AnyView(Text("文稿").frame(minWidth: 440, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)),
        inspector: AnyView(Text("建议").frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)), state: state, compact: true)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1015, height: 700),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    window.isReleasedWhenClosed = false
    window.orderFront(nil)
    defer { window.close() }
    let toolbar = controller.windowToolbar.toolbar
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    var expandedWidth: CGFloat = 0
    for compact in [true, false, true, false] {
        controller.setCompact(compact)
        window.setContentSize(NSSize(width: compact ? 1015 : 1600, height: 700))
        controller.windowToolbar.update(state, compact: compact, pickerContent: AnyView(EmptyView()))
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        let group = try #require(toolbar.items.compactMap { $0 as? NSToolbarItemGroup }.first)
        if !compact {
            let frame = try #require(window.contentView?.superview)
            let view = try #require(descendants(frame).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 5 })
            var visible = view.convert(view.bounds, to: nil)
            var ancestor = view.superview
            while let current = ancestor {
                visible = visible.intersection(current.convert(current.bounds, to: nil))
                ancestor = current.superview
            }
            #expect(visible.width >= view.fittingSize.width - 1, "All five segments must be visible, not clipped to the old popup width")
            if expandedWidth == 0 { expandedWidth = view.frame.width }
            #expect(view.frame.width >= expandedWidth - 1, "Expanded control must recover its original width")
        }
        for (index, value) in ["sideBySide", "stacked", "wipe", "reading", "source"].enumerated() {
            group.selectedIndex = index
            _ = group.target?.perform(group.action, with: group)
            #expect(selections.last == value)
            state.presentation = value
            controller.windowToolbar.update(state, compact: compact, pickerContent: AnyView(EmptyView()))
        }
    }
}

@Test @MainActor func nativeWorkspaceKeepsColumnRolesAndTracksBothToolbarDividers() throws {
    var completions = 0
    let state = WorkspaceToolbarState(filename: "很长的作文文件名.png", selectedID: UUID(), completionTitle: "完成批阅",
        canComplete: false, canExport: false, canEdit: true, canWipe: false, reviewIsSaving: false, presentation: "reading",
        editorTitle: "核对原文", importPhoto: {}, export: { _ in }, complete: { completions += 1 }, edit: {}, selectPresentation: { _ in })
    let controller = WorkspaceSplitController(sidebar: AnyView(Text("来源")), document: AnyView(Text("文稿")),
        inspector: AnyView(Text("建议")), state: state, compact: false)
    let window = NSWindow(contentViewController: controller)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.setContentSize(NSSize(width: 1480, height: 900))
    window.toolbar = controller.windowToolbar.toolbar
    controller.windowToolbar.refreshItems()
    #expect(controller.sidebarItem.behavior == .sidebar)
    #expect(controller.inspectorItem.behavior == .inspector)
    #expect(!controller.sidebarItem.canCollapse && !controller.inspectorItem.canCollapse)
    #expect(!controller.inspectorItem.canCollapseFromWindowResize)
    let toolbar = controller.windowToolbar.toolbar
    let dividers = toolbar.items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }
    #expect(dividers.map(\.dividerIndex) == [0, 1])
    #expect(dividers.allSatisfy { $0.splitView === controller.splitView })
    let completion = try #require(toolbar.items.first { $0.itemIdentifier.rawValue == "workspace.complete" })
    #expect(!completion.isEnabled)
    var modes = try #require(toolbar.items.compactMap { $0 as? NSToolbarItemGroup }.first)
    #expect(modes.selectedIndex == 3 && !modes.subitems[2].isEnabled)
    if #available(macOS 26.0, *) { #expect(completion.style == .prominent) }
    #expect(!toolbar.items.contains { $0.itemIdentifier.rawValue.lowercased().contains("toggle") })

    var ready = state; ready.canComplete = true; ready.canWipe = true; ready.presentation = "sideBySide"
    controller.setCompact(true)
    controller.windowToolbar.update(ready, compact: true, pickerContent: AnyView(Text("作业")))
    modes = try #require(toolbar.items.compactMap { $0 as? NSToolbarItemGroup }.first)
    #expect(controller.sidebarItem.isCollapsed && !controller.inspectorItem.isCollapsed)
    #expect(toolbar.items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }.map(\.dividerIndex) == [1])
    #expect(toolbar.items.contains { $0.itemIdentifier.rawValue == "workspace.assignments" })
    #expect(completion.isEnabled && modes.selectedIndex == 0 && modes.subitems[2].isEnabled)
    #expect(modes.controlRepresentation == .collapsed)
    _ = completion.target?.perform(completion.action, with: completion)
    #expect(completions == 1)
    controller.setCompact(false)
    controller.windowToolbar.update(ready, compact: false, pickerContent: AnyView(EmptyView()))
    modes = try #require(toolbar.items.compactMap { $0 as? NSToolbarItemGroup }.first)
    #expect(toolbar.items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }.map(\.dividerIndex) == [0, 1])
    #expect(!toolbar.items.contains { $0.itemIdentifier.rawValue == "workspace.assignments" })
    #expect(modes.controlRepresentation == .automatic)

    var saving = ready; saving.reviewIsSaving = true
    controller.windowToolbar.update(saving, compact: false, pickerContent: AnyView(EmptyView()))
    let undoItems = toolbar.items.filter { ["workspace.undo", "workspace.redo"].contains($0.itemIdentifier.rawValue) }
    #expect(undoItems.count == 2)
    for item in undoItems {
        item.isEnabled = true
        item.validate()
        #expect(!item.isEnabled)
    }
    let anotherToolbar = WorkspaceToolbar(splitView: controller.splitView, state: ready, compact: true)
    #expect(anotherToolbar.toolbar.identifier != toolbar.identifier)
}

@Test @MainActor func reviewToolbarKeepsTheRequestedOrderAndValidation() async throws {
    var reviews = 0
    var state = WorkspaceToolbarState(filename: "fixture.png", selectedID: UUID(), completionTitle: "完成批阅",
        canComplete: true, canExport: true, canEdit: true, canWipe: true, reviewIsSaving: false,
        presentation: "sideBySide", editorTitle: "校对识别稿", importPhoto: {}, export: { _ in },
        complete: {}, edit: {}, selectPresentation: { _ in }, canReview: true, review: { reviews += 1 })
    let controller = WorkspaceSplitController(sidebar: AnyView(Text("来源")),
        document: AnyView(Text("文稿")), inspector: AnyView(Text("建议")), state: state, compact: true)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = controller; window.orderFront(nil)
    defer { window.close() }
    let toolbar = controller.windowToolbar.toolbar
    let expected = ["workspace.review", "workspace.complete", "workspace.export"]
    for width in [800, 1480, 800] {
        window.setContentSize(NSSize(width: width, height: 600))
        controller.setCompact(width < 1180)
        controller.windowToolbar.update(state, compact: width < 1180, pickerContent: AnyView(EmptyView()))
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        let visible = (toolbar.visibleItems ?? []).map(\.itemIdentifier.rawValue).filter { expected.contains($0) }
        #expect(visible == expected, "All three review actions must remain visible and in order")
    }
    let retry = try #require(toolbar.items.first { $0.itemIdentifier.rawValue == "workspace.review" })
    #expect(retry.isEnabled)
    _ = retry.target?.perform(retry.action, with: retry)
    #expect(reviews == 1)
    state.canReview = false
    controller.windowToolbar.update(state, compact: true, pickerContent: AnyView(EmptyView()))
    #expect(!retry.isEnabled)
    _ = retry.target?.perform(retry.action, with: retry)
    #expect(reviews == 1)
    let share = try #require(toolbar.items.compactMap { $0 as? NSMenuToolbarItem }.first)
    #expect(share.menu.items.map(\.title) == ["识别结果…", "识别结果（含批注）…"])
}

/// Run separately from other live window fixtures so their layout passes don't
/// occupy the main run loop during this short animation's frame sampling.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_UI_MOTION"] == "1"))
@MainActor func nativeColumnTransitionInterpolatesAndHonorsTheLatestIntent() async throws {
    let state = WorkspaceToolbarState(filename: "动画测试", selectedID: UUID(), completionTitle: "完成批阅",
        canComplete: true, canExport: true, canEdit: true, canWipe: true, reviewIsSaving: false,
        presentation: "sideBySide", editorTitle: "校对识别稿", importPhoto: {}, export: { _ in },
        complete: {}, edit: {}, selectPresentation: { _ in })
    let controller = WorkspaceSplitController(sidebar: AnyView(Text("来源").frame(maxWidth: .infinity, maxHeight: .infinity)),
        document: AnyView(Text("文稿").frame(minWidth: 440, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)),
        inspector: AnyView(Text("建议").frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)), state: state, compact: false)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1280, height: 700),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 1280, height: 700))
    window.orderFront(nil)
    defer { window.close() }
    controller.view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(40))
    let initialFrame = window.frame
    let document = controller.splitView.arrangedSubviews[1]
    // macOS 26 extends the content view behind the glass columns and moves
    // its safe area, rather than moving the content view's frame itself.
    func documentEdge() -> CGFloat {
        document.convert(NSPoint(x: document.safeAreaRect.minX, y: 0), to: controller.splitView).x
    }
    let start = documentEdge()
    #expect(start >= WorkspaceLayout.sidebarWidth)
    controller.setCompact(true, animated: true)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        #expect(!controller.isAnimatingColumns && controller.sidebarItem.isCollapsed)
        return
    }
    #expect(controller.isAnimatingColumns)
    var edges: [CGFloat] = [start]
    for _ in 0..<9 {
        try await Task.sleep(for: .milliseconds(30))
        edges.append(documentEdge())
    }
    #expect(edges.contains { $0 > 1 && $0 < start - 1 }, "Expected intermediate frames, got \(edges)")
    #expect(edges.allSatisfy { $0 >= -1 && $0 <= start + 1 })
    #expect(controller.sidebarItem.isCollapsed && !controller.isAnimatingColumns)
    #expect(abs(documentEdge()) <= 1)
    #expect(window.frame == initialFrame)

    controller.setCompact(false, animated: true)
    try await Task.sleep(for: .milliseconds(40))
    controller.setCompact(true, animated: true)
    try await Task.sleep(for: .milliseconds(40))
    controller.setCompact(false, animated: true)
    try await Task.sleep(for: .milliseconds(300))
    #expect(!controller.sidebarItem.isCollapsed && !controller.isCompact && !controller.isAnimatingColumns)
    #expect(abs(documentEdge() - start) <= 1)
    #expect(!controller.inspectorItem.isCollapsed)

    // Reduce Motion can turn on while a transition is already in progress.
    controller.setCompact(true, animated: true)
    try await Task.sleep(for: .milliseconds(30))
    controller.setCompact(true, animated: false)
    try await Task.sleep(for: .milliseconds(260))
    #expect(controller.sidebarItem.isCollapsed && !controller.isAnimatingColumns)
    #expect(abs(documentEdge()) <= 1)
}

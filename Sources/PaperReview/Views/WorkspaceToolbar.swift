import AppKit
import SwiftUI

/// SwiftUI owns the work and presentations. AppKit owns only the native window
/// toolbar, its glass groups and separators that track the real split panes.
struct WorkspaceToolbarState {
    var filename: String
    var selectedID: UUID?
    var completionTitle: String
    var canComplete: Bool
    var canExport: Bool
    var canEdit: Bool
    var canWipe: Bool
    var reviewIsSaving: Bool
    var presentation: String
    var editorTitle: String
    var importPhoto: () -> Void
    var export: (Bool) -> Void
    var complete: () -> Void
    var edit: () -> Void
    var selectPresentation: (String) -> Void
    var canReview = false
    var review: () -> Void = {}
}

final class WorkspaceToolbar: NSObject, NSToolbarDelegate {
    private enum ID {
        static let assignments = NSToolbarItem.Identifier("workspace.assignments")
        static let importPhoto = NSToolbarItem.Identifier("workspace.import")
        static let sourceDivider = NSToolbarItem.Identifier("workspace.source-divider")
        static let title = NSToolbarItem.Identifier("workspace.title")
        static let modes = NSToolbarItem.Identifier("workspace.modes")
        static let undo = NSToolbarItem.Identifier("workspace.undo")
        static let redo = NSToolbarItem.Identifier("workspace.redo")
        static let edit = NSToolbarItem.Identifier("workspace.edit")
        static let reviewDivider = NSToolbarItem.Identifier("workspace.review-divider")
        static let reviewTitle = NSToolbarItem.Identifier("workspace.review-title")
        static let export = NSToolbarItem.Identifier("workspace.export")
        static let complete = NSToolbarItem.Identifier("workspace.complete")
        static let review = NSToolbarItem.Identifier("workspace.review")
    }
    private static let presentations = ["sideBySide", "stacked", "wipe", "reading", "source"]
    private static let modeTitles = ["左右对照", "上下对照", "滑动对照", "阅读识别稿", "单独查看原稿"]
    private static let modeSymbols = ["rectangle.split.2x1", "rectangle.split.1x2", "rectangle.lefthalf.filled", "book", "viewfinder"]
    let toolbar = NSToolbar(identifier: "PaperReview.workspace.\(UUID().uuidString)")
    private weak var splitView: NSSplitView?
    private var compact = false
    private var state: WorkspaceToolbarState
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let titleField = NSTextField(labelWithString: "")
    private var titleWidth: NSLayoutConstraint?
    private let picker = NSPopover()
    private let pickerHost = NSHostingController(rootView: AnyView(EmptyView()))

    init(splitView: NSSplitView, state: WorkspaceToolbarState, compact: Bool) {
        self.splitView = splitView; self.state = state; self.compact = compact
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        picker.behavior = .transient
        picker.contentViewController = pickerHost
        picker.contentSize = NSSize(width: 260, height: 520)
    }

    func update(_ state: WorkspaceToolbarState, compact: Bool, pickerContent: AnyView) {
        if self.state.selectedID != state.selectedID || !compact { picker.close() }
        self.state = state
        pickerHost.rootView = pickerContent
        if self.compact != compact {
            self.compact = compact
            // Replace the source-column section when the assignment list
            // becomes a compact picker; keep the other action items alive.
            if compact {
                if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == ID.sourceDivider }) { toolbar.removeItem(at: index) }
                if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == ID.importPhoto }) { toolbar.removeItem(at: index) }
                if !toolbar.items.contains(where: { $0.itemIdentifier == ID.assignments }) { toolbar.insertItem(withItemIdentifier: ID.assignments, at: 0) }
            } else {
                if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == ID.assignments }) { toolbar.removeItem(at: index) }
                toolbar.insertItem(withItemIdentifier: ID.importPhoto, at: 0)
                toolbar.insertItem(withItemIdentifier: ID.sourceDivider, at: 1)
            }
            // Changing a live group's representation can leave its new
            // segmented control inside the old popup's narrow toolbar slot.
            // Replace only this native item when the composition changes so
            // AppKit measures the correct representation from the outset.
            items[ID.modes] = nil
            if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == ID.modes }) {
                toolbar.removeItem(at: index)
                toolbar.insertItem(withItemIdentifier: ID.modes, at: index)
            }
        }
        titleField.stringValue = state.filename
        titleField.toolTip = state.filename
        items[ID.complete]?.title = state.completionTitle
        items[ID.complete]?.label = state.completionTitle
        items[ID.complete]?.isEnabled = state.canComplete
        items[ID.export]?.isEnabled = state.canExport
        items[ID.review]?.isEnabled = state.canReview
        items[ID.edit]?.isEnabled = state.canEdit
        items[ID.edit]?.toolTip = state.editorTitle
        for id in [ID.undo, ID.redo] {
            if let item = items[id] as? WorkspaceUndoToolbarItem {
                item.reviewIsSaving = state.reviewIsSaving
                item.validate()
            }
        }
        if let group = items[ID.modes] as? NSToolbarItemGroup {
            group.selectedIndex = Self.presentations.firstIndex(of: state.presentation) ?? 0
            group.subitems[2].isEnabled = state.canWipe
            group.isEnabled = state.selectedID != nil
        }
        updateTitleWidth()
    }

    func refreshItems() { update(state, compact: compact, pickerContent: pickerHost.rootView) }

    func updateTitleWidth() {
        guard let splitView, splitView.arrangedSubviews.count == 3 else { return }
        let width = splitView.arrangedSubviews[1].frame.width
        titleWidth?.constant = WorkspaceLayout.documentTitleWidth(in: width, compact: compact)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let source: [NSToolbarItem.Identifier] = compact ? [ID.assignments] : [ID.importPhoto, ID.sourceDivider]
        return source + [ID.title, .flexibleSpace, ID.modes, .space, ID.undo, ID.redo, ID.edit,
            ID.reviewDivider, ID.reviewTitle, .flexibleSpace, ID.review, .space, ID.complete, .space, ID.export, .space]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if let existing = items[id] { return existing }
        let item: NSToolbarItem
        switch id {
        case ID.sourceDivider, ID.reviewDivider:
            guard let splitView else { return nil }
            item = NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitView, dividerIndex: id == ID.sourceDivider ? 0 : 1)
        case ID.title, ID.reviewTitle:
            item = NSToolbarItem(itemIdentifier: id)
            let field = id == ID.title ? titleField : NSTextField(labelWithString: "批阅建议")
            field.font = .systemFont(ofSize: 13, weight: .semibold)
            field.lineBreakMode = .byTruncatingMiddle
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if id == ID.title {
                titleWidth = field.widthAnchor.constraint(equalToConstant: 180)
                titleWidth?.isActive = true
            }
            // Tracking separators contribute a 5pt title inset on macOS.
            // Use the shared 20pt content edge for the text, not for glass buttons.
            let title = NSStackView(views: [field])
            title.orientation = .horizontal
            title.edgeInsets = NSEdgeInsets(top: 0, left: WorkspaceGrid.paneInset - 5, bottom: 0, right: 0)
            item.view = title; item.isBordered = false
            item.label = id == ID.title ? "作业名称" : "批阅建议"
            item.visibilityPriority = .high
        case ID.modes:
            let group = NSToolbarItemGroup(itemIdentifier: id,
                images: zip(Self.modeSymbols, Self.modeTitles).map { NSImage(systemSymbolName: $0.0, accessibilityDescription: $0.1)! },
                selectionMode: .selectOne, labels: Self.modeTitles, target: self, action: #selector(changePresentation(_:)))
            group.label = "文稿视图"; group.isBordered = true
            group.controlRepresentation = compact ? .collapsed : .automatic
            group.autovalidates = false
            for (index, child) in group.subitems.enumerated() {
                child.toolTip = Self.modeTitles[index]; child.autovalidates = false
            }
            item = group
        case ID.export:
            let menuItem = NSMenuToolbarItem(itemIdentifier: id)
            menuItem.label = "导出"; menuItem.toolTip = "导出识别结果"
            menuItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "导出")
            menuItem.showsIndicator = false; menuItem.isBordered = true; menuItem.autovalidates = false
            let menu = NSMenu()
            for (index, title) in ["识别结果…", "识别结果（含批注）…"].enumerated() {
                let action = NSMenuItem(title: title, action: #selector(exportDocument(_:)), keyEquivalent: "")
                action.tag = index; action.target = self; menu.addItem(action)
            }
            menuItem.menu = menu; item = menuItem
            item.visibilityPriority = .user
        case ID.review:
            item = button(id, title: "重新审核", symbol: "arrow.clockwise", action: #selector(review))
            item.visibilityPriority = .user
        case ID.complete:
            item = button(id, title: state.completionTitle, symbol: nil, action: #selector(complete))
            item.possibleLabels = ["完成批阅", "下一份"]
            item.visibilityPriority = .user
            if #available(macOS 26.0, *) { item.style = .prominent; item.backgroundTintColor = WorkspaceStyle.actionColor }
        case ID.importPhoto:
            item = button(id, title: "导入照片", symbol: "plus", action: #selector(importPhoto))
        case ID.assignments:
            item = button(id, title: "选择或导入作业", symbol: "tray", action: #selector(showAssignments(_:)))
            let control = NSButton(image: NSImage(systemSymbolName: "tray", accessibilityDescription: "选择或导入作业")!,
                target: self, action: #selector(showAssignments(_:)))
            control.bezelStyle = .texturedRounded
            control.setAccessibilityLabel("选择或导入作业")
            item.view = control; item.isBordered = true
            item.visibilityPriority = .user
        case ID.edit:
            item = button(id, title: "校对识别稿", symbol: "pencil", action: #selector(edit))
        case ID.undo, ID.redo:
            item = button(id, title: id == ID.undo ? "撤销" : "重做",
                symbol: id == ID.undo ? "arrow.uturn.backward" : "arrow.uturn.forward",
                action: NSSelectorFromString(id == ID.undo ? "undo:" : "redo:"))
            item.target = nil; item.autovalidates = true; item.visibilityPriority = .low
        default: return nil
        }
        items[id] = item
        return item
    }
    private func button(_ id: NSToolbarItem.Identifier, title: String, symbol: String?, action: Selector) -> NSToolbarItem {
        let item: NSToolbarItem = (id == ID.undo || id == ID.redo)
            ? WorkspaceUndoToolbarItem(itemIdentifier: id) : NSToolbarItem(itemIdentifier: id)
        item.label = title; item.toolTip = title
        if symbol == nil { item.title = title }
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
        item.target = self; item.action = action; item.isBordered = true; item.autovalidates = false
        return item
    }
    @objc private func importPhoto() { picker.close(); state.importPhoto() }
    @objc private func exportDocument(_ sender: NSMenuItem) { state.export(sender.tag == 1) }
    @objc private func complete() { state.complete() }
    @objc private func review() { if state.canReview { state.review() } }
    @objc private func edit() { state.edit() }
    @objc private func changePresentation(_ sender: NSToolbarItemGroup) {
        guard Self.presentations.indices.contains(sender.selectedIndex), sender.selectedIndex != 2 || state.canWipe else { return }
        state.selectPresentation(Self.presentations[sender.selectedIndex])
    }
    @objc private func showAssignments(_ sender: Any) {
        guard let anchor = (sender as? NSView) ?? (sender as? NSToolbarItem)?.view else { return }
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}

/// Preserve the existing save-in-flight guard while keeping AppKit's responder
/// chain validation for document editing, text fields and native undo menus.
private final class WorkspaceUndoToolbarItem: NSToolbarItem {
    var reviewIsSaving = false
    override func validate() {
        super.validate()
        if reviewIsSaving { isEnabled = false }
    }
}

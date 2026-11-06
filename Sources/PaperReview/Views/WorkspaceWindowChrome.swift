import AppKit

/// Full-height native columns retain the standard window controls and toolbar.
enum WorkspaceWindowChrome {
    static func configure(_ window: NSWindow) -> CGFloat {
        guard window.styleMask.contains(.titled) else { return 0 }
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
        // The native toolbar supplies a leading title in the document column.
        // Keep NSWindow.title for menus/accessibility, but not across the sidebar seam.
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if window.toolbar?.showsBaselineSeparator == true { window.toolbar?.showsBaselineSeparator = false }
        return max(0, window.frame.height - window.contentLayoutRect.height)
    }
}

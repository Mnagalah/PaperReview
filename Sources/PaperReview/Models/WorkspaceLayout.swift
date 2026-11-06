import SwiftUI

/// Shared pane tracks, not per-control offsets. Both columns keep the same
/// context and footer baselines as content and review state change.
enum WorkspaceGrid {
    static let paneInset: CGFloat = 20
    static let contextHeight: CGFloat = 64
    static let footerHeight: CGFloat = 44
    static let controlHeight: CGFloat = 32
    static let controlGap: CGFloat = 12
    static let documentGap: CGFloat = 20
    static let readingInset: CGFloat = 40
}

/// Review is always a document + inspector workspace. Narrow windows move the
/// assignment list into a picker; they never become a document-only workspace.
struct WorkspaceLayout {
    static let minimumWidth: CGFloat = 800
    static let minimumHeight: CGFloat = 600
    static let sidebarWidth: CGFloat = 216
    static let documentMinimumWidth: CGFloat = 440
    static let inspectorMinimumWidth: CGFloat = 300
    static let compactBreakpoint: CGFloat = 1180
    static let resizeHysteresis: CGFloat = 24
    let width: CGFloat
    var compact: Bool { width < Self.compactBreakpoint }
    /// Keep the current composition near the breakpoint instead of flapping
    /// between two layouts when a window edge moves by a few points.
    static func compactAfterResize(width: CGFloat, wasCompact: Bool) -> Bool {
        width < compactBreakpoint + (wasCompact ? resizeHysteresis : -resizeHysteresis)
    }
    var sidebarVisible: Bool { !compact }
    var workplaneWidth: CGFloat { width - (sidebarVisible ? Self.sidebarWidth + 1 : 0) }
    static func documentTitleWidth(in documentWidth: CGFloat, compact: Bool = false) -> CGFloat {
        max(70, min(240, documentWidth - (compact ? 440 : 320)))
    }
}

enum WorkspaceMotion {
    static let columnDuration: TimeInterval = 0.22
}

/// A sheet must fit its owning workspace instead of increasing the parent
/// window's minimum size. Both dimensions are in points, not display pixels.
struct TranscriptEditorLayout {
    let availableSize: CGSize
    var size: CGSize {
        CGSize(width: min(940, max(600, availableSize.width - 48)),
               height: min(650, max(460, availableSize.height - 80)))
    }
    var sideBySide: Bool { size.width >= 820 }
}

private struct WorkspaceSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1480, height: 920)
}

extension EnvironmentValues {
    var workspaceSize: CGSize {
        get { self[WorkspaceSizeKey.self] }
        set { self[WorkspaceSizeKey.self] = newValue }
    }
}

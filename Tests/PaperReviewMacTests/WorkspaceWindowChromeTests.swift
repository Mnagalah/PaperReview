import AppKit
import Testing
@testable import PaperReview

@Test @MainActor func workspaceChromeExtendsContentWithoutReplacingNativeWindowControls() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.title = "作业批改 — 作文.png"
    window.toolbar = NSToolbar(identifier: "workspace-chrome-test")
    let height = WorkspaceWindowChrome.configure(window)
    #expect(window.titlebarAppearsTransparent)
    #expect(window.titleVisibility == .hidden)
    #expect(window.styleMask.contains(.fullSizeContentView))
    #expect(window.styleMask.contains(.closable) && window.styleMask.contains(.resizable))
    #expect(window.standardWindowButton(.closeButton) != nil && window.isMovable)
    #expect(window.standardWindowButton(.miniaturizeButton) != nil)
    #expect(window.standardWindowButton(.zoomButton) != nil)
    #expect(window.toolbar?.isVisible == true && window.toolbar?.showsBaselineSeparator == false)
    #expect(window.titlebarSeparatorStyle == .none)
    #expect(window.title == "作业批改 — 作文.png" && height > 0)
    #expect(WorkspaceWindowChrome.configure(window) == height)
}

@Test @MainActor func workspaceChromeDoesNotInventAHeaderForBorderlessRenderingFixtures() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
        styleMask: [.borderless], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    #expect(WorkspaceWindowChrome.configure(window) == 0)
    #expect(!window.styleMask.contains(.titled))
}

import AppKit
import Testing
@testable import PaperReview

@Test func workspaceTitlePreservesImportedFilenameAndReopensOlderAssignments() throws {
    var record = AssignmentRecord(title: "周末作文", originalFilename: "original.jpg")
    #expect(record.displayFilename == "周末作文.jpg")
    record.importedFilename = "周末作文.JPG"
    let reopened = try JSONDecoder().decode(AssignmentRecord.self, from: JSONEncoder().encode(record))
    #expect(reopened.displayFilename == "周末作文.JPG")
    #expect(reopened.originalFilename == "original.jpg")
}

@Test @MainActor func workspaceThemeHasAUserControlledDarkDefaultAndARealSystemOption() {
    #expect(WorkspaceAppearance.dark.colorScheme == .dark)
    #expect(WorkspaceAppearance.system.colorScheme == nil)
    #expect(WorkspaceAppearance.allCases.map(\.title) == ["深色", "浅色", "跟随系统"])
    #expect(WorkspaceAppearance.light.colorScheme == .light)
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let resolved = NSAppearance(named: appearance)!
        resolved.performAsCurrentDrawingAppearance {
            for surface in [WorkspaceStyle.canvasColor, WorkspaceStyle.pageColor, WorkspaceStyle.sidebarColor,
                            WorkspaceStyle.panelColor, WorkspaceStyle.selectionColor] {
                let rgb = surface.usingColorSpace(.deviceRGB)!
                #expect(abs(rgb.redComponent - rgb.greenComponent) < 0.035)
                #expect(abs(rgb.blueComponent - rgb.greenComponent) < 0.05)
            }
        }
    }
}

@Test @MainActor func lightAnnotationsHaveAVisibleStrokeAndTintWithoutChangingDarkMode() {
    let color = WorkspaceStyle.grammarColor
    let light = WorkspaceStyle.annotationAttributes(color: color, light: true)
    let dark = WorkspaceStyle.annotationAttributes(color: color, light: false)
    #expect(light[.underlineStyle] as? Int == NSUnderlineStyle.thick.rawValue)
    #expect((light[.backgroundColor] as? NSColor)?.alphaComponent == 0.12)
    #expect(dark[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    #expect(dark[.backgroundColor] == nil)
    #expect(ReviewScroller.isCompatibleWithOverlayScrollers)
}

@Test @MainActor func customColorRolesMaintainContrastInAllFourPaletteVariants() throws {
    func luminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { Issue.record("Cannot resolve color in sRGB"); return 0 }
        func linear(_ value: CGFloat) -> Double { value <= 0.04045 ? Double(value / 12.92) : pow(Double((value + 0.055) / 1.055), 2.4) }
        return linear(rgb.redComponent) * 0.2126 + linear(rgb.greenComponent) * 0.7152 + linear(rgb.blueComponent) * 0.0722
    }
    func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    for dark in [false, true] {
        for increased in [false, true] {
            func resolve(_ role: WorkspacePaletteColor) -> NSColor { role.resolved(dark: dark, increasedContrast: increased) }
            for ink in [WorkspacePalette.spelling, WorkspacePalette.grammar, WorkspacePalette.photoFocus, WorkspacePalette.warning] {
                for surface in [WorkspacePalette.page, WorkspacePalette.panel, WorkspacePalette.canvas] {
                    #expect(ratio(resolve(ink), resolve(surface)) >= 4.5)
                }
            }
            #expect(ratio(.white, resolve(WorkspacePalette.action)) >= 4.5)
            #expect(ratio(resolve(WorkspacePalette.imageFocus), .white) >= 4.5)
            if !dark { #expect(ratio(resolve(WorkspacePalette.scroller), resolve(WorkspacePalette.panel)) >= 3) }
        }
    }
}

@Test @MainActor func reviewScrollerRetainsNativeStyleTargetAndScrollPosition() throws {
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
    scroll.hasVerticalScroller = true
    let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1200))
    scroll.documentView = document
    let before = try #require(scroll.verticalScroller)
    let style = before.scrollerStyle, target = before.target, action = before.action
    let anchor = ReviewScrollAppearance.Anchor()
    anchor.light = true; document.addSubview(anchor); anchor.install()
    let after = try #require(scroll.verticalScroller as? ReviewScroller)
    #expect(after.scrollerStyle == style)
    #expect(after.target === target && after.action == action)
    #expect(after.light)
    scroll.contentView.scroll(to: CGPoint(x: 0, y: 180))
    scroll.reflectScrolledClipView(scroll.contentView)
    let position = scroll.contentView.bounds.origin
    anchor.light = false; anchor.install()
    #expect(scroll.verticalScroller === after)
    #expect(!after.light)
    #expect(scroll.contentView.bounds.origin == position)
}

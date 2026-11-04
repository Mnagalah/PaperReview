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
    #expect(WorkspaceAppearance.allCases.map(\.title) == ["深色", "跟随系统"])
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let resolved = NSAppearance(named: appearance)!
        resolved.performAsCurrentDrawingAppearance {
            for surface in [WorkspaceStyle.canvasColor, WorkspaceStyle.pageColor, WorkspaceStyle.sidebarColor,
                            WorkspaceStyle.panelColor, WorkspaceStyle.actionColor, WorkspaceStyle.selectionColor] {
                let rgb = surface.usingColorSpace(.deviceRGB)!
                #expect(abs(rgb.redComponent - rgb.greenComponent) < 0.001)
                #expect(abs(rgb.blueComponent - rgb.greenComponent) < 0.001)
            }
        }
    }
}

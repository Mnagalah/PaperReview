import SwiftUI
import Testing
@testable import PaperReview

@Test @MainActor func workspaceLayoutFitsBetweenWindowPresetsAndAtColumnBoundaries() {
    let widths = Array(stride(from: CGFloat(800), through: 2200, by: 13.25)) + [1179.5, 1180, 1180.5]
    for width in widths {
        let layout = WorkspaceLayout(width: width)
        let documentWidth = layout.workplaneWidth - WorkspaceLayout.inspectorMinimumWidth - 1
        #expect(documentWidth >= WorkspaceLayout.documentMinimumWidth)
        #expect(WorkspaceLayout.documentTitleWidth(in: documentWidth) >= 70 && WorkspaceLayout.documentTitleWidth(in: documentWidth) <= 240)
        #expect(layout.sidebarVisible == (width >= 1180))
    }
}

@Test @MainActor func assignmentListAdaptsWithoutOfferingAReviewPaneCollapseState() {
    let widths: [CGFloat] = [1480, 1137, 937, 803.5, 1179.5, 1180, 1573]
    let layouts = widths.map { WorkspaceLayout(width: $0) }
    #expect(layouts.first!.sidebarVisible && layouts.last!.sidebarVisible)
    #expect(layouts[1...4].allSatisfy { $0.compact })
    #expect(layouts[5].sidebarVisible)
}

@Test @MainActor func responsiveColumnsDoNotChatterNearTheBreakpoint() {
    var compact = false
    for width: CGFloat in [1240, 1180, 1179, 1160, 1156] {
        compact = WorkspaceLayout.compactAfterResize(width: width, wasCompact: compact)
        #expect(!compact)
    }
    compact = WorkspaceLayout.compactAfterResize(width: 1155, wasCompact: compact)
    #expect(compact)
    for width: CGFloat in [1156, 1179, 1181, 1200, 1203, 1175, 1203] {
        compact = WorkspaceLayout.compactAfterResize(width: width, wasCompact: compact)
        #expect(compact)
    }
    compact = WorkspaceLayout.compactAfterResize(width: 1204, wasCompact: compact)
    #expect(!compact)
    #expect(WorkspaceLayout.compactAfterResize(width: 800, wasCompact: false))
    #expect(!WorkspaceLayout.compactAfterResize(width: 2200, wasCompact: true))
}

@Test @MainActor func proofreadingSheetFitsItsOwningWindowWithoutEnlargingIt() {
    for width in stride(from: CGFloat(800), through: 2100, by: 17.5) {
        for height in stride(from: CGFloat(600), through: 1200, by: 31.25) {
            let layout = TranscriptEditorLayout(availableSize: CGSize(width: width, height: height))
            #expect(layout.size.width <= width - 48)
            #expect(layout.size.height <= height - 80)
            #expect(layout.size.width >= 600 && layout.size.height >= 460)
            #expect(layout.sideBySide == (layout.size.width >= 820))
        }
    }
    #expect(!TranscriptEditorLayout(availableSize: CGSize(width: 800, height: 600)).sideBySide)
    #expect(TranscriptEditorLayout(availableSize: CGSize(width: 1480, height: 920)).size == CGSize(width: 940, height: 650))
}

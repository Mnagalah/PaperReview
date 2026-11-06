import AppKit
import SwiftUI
import Testing
import PaperReviewCore
@testable import PaperReview

/// Native rendering fixtures are opt-in and contain synthetic content only.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_UI_SNAPSHOTS"] != nil))
@MainActor func captureWorkspaceAtSupportedWindowSizes() async throws {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PAPERREVIEW_UI_SNAPSHOTS"]!)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-snapshot-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(models: SnapshotModelModule(), dataRoot: root)
    let text = "Last weekend, I have a wonderful time with my family.\nOn Saturday morning, we go to the park and have a picnic.\nThe wether is suny and warm.\nIn the afternoon, i finish my homework. On Sunday, I visit my\ngrandparents and help they clean the house.\nI feeled tired but happy."
    let hints = text.split(separator: "\n").enumerated().map { index, line in
        TextHint(text: String(line), rect: .init(x: 0.04, y: 0.1 + Double(index) * 0.10, width: 0.90, height: 0.06), confidence: 1)
    }
    let transcript = LineAlignment.makeTranscript(text: text, hints: hints)
    var record = AssignmentRecord(title: "合成作文", originalFilename: "original.png")
    record.importedFilename = "合成作文（界面测试）.png"; record.transcript = transcript; record.phase = .complete
    record.issues = IssueAnchoring.anchor([
        .init(line: 1, quote: "have", occurrence: 1, kind: .grammar, suggestion: "had", explanation: "叙述过去的经历，动词使用过去式。"),
        .init(line: 2, quote: "go", occurrence: 1, kind: .grammar, suggestion: "went", explanation: "与上下文的过去时间保持一致。"),
        .init(line: 3, quote: "suny", occurrence: 1, kind: .spelling, suggestion: "sunny", explanation: "单词缺少字母 n。")
    ], to: transcript).issues
    let job = Assignment(record: record)
    let source = TranscriptPageView()
    source.transcript = transcript; source.paperBackground = true; source.pageHeight = 750
    source.frame = NSRect(x: 0, y: 0, width: 1000, height: 750)
    let sourceBitmap = try #require(source.bitmapImageRepForCachingDisplay(in: source.bounds))
    source.cacheDisplay(in: source.bounds, to: sourceBitmap)
    job.sourceImage = NSImage(data: try #require(sourceBitmap.representation(using: .png, properties: [:])))
    job.enhancedImage = job.sourceImage
    job.record.width = 1000; job.record.height = 750
    store.assignments = [job]; store.selectedID = job.id; store.selectedIssueID = record.issues.first?.id
    for (width, height, reading, light) in [(1440, 900, false, false), (1280, 800, false, false),
        (1024, 768, true, false), (1024, 768, true, true),
        (800, 600, false, false), (800, 600, true, true), (937, 641, true, false)] {
        job.reading.presentation = reading ? "reading" : "sideBySide"
        let host = NSHostingView(rootView: ContentView(store: store)
            .environment(\.colorScheme, light ? .light : .dark).tint(WorkspaceStyle.action))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let name = "native-\(width)x\(height)-\(reading ? "reading" : "paired")-\(light ? "light" : "dark").png"
        try png.write(to: output.appendingPathComponent(name))
        #expect(host.frame.width == CGFloat(width))
        window.close()
    }
    for (width, height) in [(800, 600), (1480, 920)] {
        let available = CGSize(width: width, height: height)
        let size = TranscriptEditorLayout(availableSize: available).size
        let host = NSHostingView(rootView: TranscriptEditor(store: store, job: job)
            .environment(\.workspaceSize, available).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("editor-\(width)x\(height).png"))
        #expect(host.fittingSize.width <= size.width)
        #expect(host.fittingSize.height <= size.height)
        window.close()
    }
    await store.finishReadingWrites()
}

@Test @MainActor func selectedWordFocusUsesTheWordRatherThanAnOffscreenWholeRow() throws {
    let text = "Last weekend, I have a wonderful time with my family."
    let transcript = Transcript(text: text, lines: [.init(id: 1, start: 0, length: text.utf16.count,
        rect: .init(x: 0.05, y: 0.1, width: 0.9, height: 0.05))], isAligned: true)
    let page = TranscriptPageView(); page.transcript = transcript; page.zoom = 1; page.pageHeight = 700
    page.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
    let issue = IssueAnchoring.anchor([.init(line: 1, quote: "have", occurrence: 1, kind: .grammar,
        suggestion: "had", explanation: "fixture")], to: transcript).issues[0]
    let target = try #require(page.focusRect(for: issue))
    #expect(target.width > 20 && target.width < 60)
    #expect(target.minX > 45 && target.maxX < 900)
}

@MainActor private final class SnapshotModelModule: ModelModule {
    var readiness = ModelReadiness(required: [])
    var policy: RecognitionPolicy { .init(threshold: 0.5, maximumAttempts: 3) }
    var needsTerminationPreparation: Bool { false }
    func makeSession() throws -> any ModelSession { throw ModelError.unavailable("synthetic fixture") }
    func checkReadiness() async {}
    func prepareForTermination() async {}
}

/// Resizes one live AppKit hierarchy, rather than constructing a new view at a
/// handful of presets. This checks layout/state, not pointer-driven resizing.
@Test @MainActor func continuousWindowResizeKeepsDocumentInBoundsAndRetainsSelection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-resize-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(models: SnapshotModelModule(), dataRoot: root)
    var record = AssignmentRecord(title: "响应式合成夹具", originalFilename: "fixture.png")
    record.transcript = LineAlignment.fallback("The wether is suny.\nI feeled happy.")
    record.phase = .complete; record.width = 1000; record.height = 750
    record.issues = IssueAnchoring.anchor([.init(line: 1, quote: "suny", occurrence: 1,
        kind: .spelling, suggestion: "sunny", explanation: "拼写合成夹具")], to: record.transcript!).issues
    let job = Assignment(record: record); job.reading.zoom = 1.25
    store.assignments = [job]; store.selectedID = job.id; store.selectedIssueID = record.issues.first?.id
    let host = NSHostingView(rootView: ContentView(store: store))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 900),
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    var documentIdentity: ObjectIdentifier?
    var expectedCompact = false
    let narrowing = Array(stride(from: CGFloat(1600), through: 800, by: -12.5))
    for (index, width) in (narrowing + narrowing.reversed()).enumerated() {
        let height = CGFloat(600 + (index % 17) * 19)
        window.setContentSize(CGSize(width: width, height: height))
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        let document = try #require(descendants(host).compactMap { $0 as? PairedScrollView }.first)
        let rect = document.convert(document.bounds, to: host)
        #expect(rect.minX >= -1 && rect.maxX <= host.bounds.width + 1)
        #expect(rect.width >= WorkspaceLayout.documentMinimumWidth - 1)
        #expect(rect.minY >= -1 && rect.maxY <= host.bounds.height + 1)
        let split = try #require(descendants(host).compactMap { $0 as? NSSplitView }.first)
        #expect(split.arrangedSubviews.count == 3)
        if width < 1156 { expectedCompact = true }
        else if width >= 1204 { expectedCompact = false }
        #expect(split.isSubviewCollapsed(split.arrangedSubviews[0]) == expectedCompact)
        #expect(split.arrangedSubviews.last!.frame.width >= WorkspaceLayout.inspectorMinimumWidth)
        #expect(!split.isSubviewCollapsed(split.arrangedSubviews.last!))
        #expect(document.source.frame == document.text.frame)
        if let documentIdentity { #expect(ObjectIdentifier(document) == documentIdentity) }
        else { documentIdentity = ObjectIdentifier(document) }
        #expect(store.selectedIssueID == record.issues.first?.id)
        #expect(job.reading.zoom == 1.25 && job.reading.presentation == "sideBySide")
    }
    await store.finishReadingWrites()
}

/// Warning visibility must not change the source viewport or the shared tracks.
@Test @MainActor func readabilityWarningDoesNotMoveTheDocumentViewport() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-grid-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(models: SnapshotModelModule(), dataRoot: root)
    let transcript = LineAlignment.fallback(Array(repeating: "suny", count: 10).joined(separator: " "))
    let hints = (0..<10).map { WordHint(lineID: 1, text: "suny",
        rect: .init(x: 0.05 + Double($0) * 0.08, y: 0.1, width: 0.06, height: 0.1), confidence: 1) }
    let checks = WordAlignment.inventory(transcript, hints: hints).regions.map {
        WordCheck(region: $0, isolated: nil, sourceReading: nil, sourceChecked: true)
    }
    let evidence = ReadabilityEvidence(checks: checks, totalRegions: 10)
    var record = AssignmentRecord(title: "grid", originalFilename: "synthetic.png")
    record.phase = .complete; record.transcript = transcript; record.width = 400; record.height = 300
    let job = Assignment(record: record)
    job.setPage(PreparedPage(source: Data(), enhanced: Data(), strong: nil, width: 400, height: 300,
        hints: [], words: [], readingRegions: [ReadingOrder.fullPage], annotations: [], cropped: false,
        scan: ScanMetadata(version: PhotoProcessor.version, perspectiveCorrected: false,
            originalWidth: 400, originalHeight: 300, corners: [], pages: nil)))
    store.assignments = [job]; store.selectedID = job.id
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for width in [800, 937, 1480] {
        job.record.candidates = []
        let host = NSHostingView(rootView: ContentView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded(); await Task.yield(); host.layoutSubtreeIfNeeded()
        let document = try #require(descendants(host).compactMap { $0 as? PairedScrollView }.first)
        let baseline = document.convert(document.bounds, to: host)
        #expect(!job.hasPoorReadability)
        job.record.candidates = [OCRCandidate(attempt: 1, transcript: transcript, score: 0.9,
            scoredSourceVersion: PhotoProcessor.version, readability: evidence)]
        job.record.rejectedIssues = 1
        #expect(job.hasPoorReadability)
        await Task.yield(); host.layoutSubtreeIfNeeded()
        #expect(document.convert(document.bounds, to: host) == baseline)
        job.record.candidates = []; job.record.rejectedIssues = 0
        await Task.yield(); host.layoutSubtreeIfNeeded()
        #expect(document.convert(document.bounds, to: host) == baseline)
        window.close()
    }
    await store.finishReadingWrites()
}

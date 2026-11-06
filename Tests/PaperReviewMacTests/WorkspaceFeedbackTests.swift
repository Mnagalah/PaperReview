import AppKit
import SwiftUI
import Testing
import PaperReviewCore
@testable import PaperReview

@Test @MainActor func liquidDotsCycleMergesSeparatesAndLoopsWithoutOvershoot() {
    #expect(LiquidDotsLoader.separation(at: 0) == 0)
    #expect(abs(LiquidDotsLoader.separation(at: 0.8) - 14) < 0.001)
    #expect(abs(LiquidDotsLoader.separation(at: 1.6)) < 0.001)
    for tick in 0...160 {
        #expect((0...14).contains(LiquidDotsLoader.separation(at: Double(tick) / 100)))
    }
    #expect(PipelinePhase.recognizing.title == "正在转写")
}

/// Synthetic native render only: no model calls, no formal assignment data.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_UI_FEEDBACK"] != nil))
@MainActor func captureProcessingFeedbackAtWideAndMinimumSizes() async throws {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PAPERREVIEW_UI_FEEDBACK"]!)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-feedback-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    _ = NSApplication.shared
    let oldAppearance = NSApp.appearance
    defer { NSApp.appearance = oldAppearance }
    let store = WorkspaceStore(models: FeedbackModelModule(), dataRoot: root)
    var record = AssignmentRecord(title: "进度合成夹具", originalFilename: "IMG_1081.HEIC")
    record.importedFilename = "IMG_1081.HEIC"
    record.transcript = LineAlignment.fallback("I feeled happy. The wether is suny.")
    record.width = 1000; record.height = 750
    record.phase = .verifyingWords; record.wordChecksCompleted = 24; record.wordChecksTotal = 50
    record.issues = IssueAnchoring.anchor([
        .init(line: 1, quote: "feeled", occurrence: 1, kind: .spelling, suggestion: "felt", explanation: "过去式。"),
        .init(line: 1, quote: "suny", occurrence: 1, kind: .spelling, suggestion: "sunny", explanation: "缺少 n。")
    ], to: record.transcript!).issues
    let issues = record.issues; record.issues = []
    let job = Assignment(record: record)
    store.assignments = [job]; store.selectedID = job.id
    for (width, height, phase, light) in [(1480, 900, PipelinePhase.verifyingWords, false),
        (800, 600, .verifyingWords, false), (800, 600, .recognizing, true),
        (800, 600, .complete, false)] {
        job.record.phase = phase
        job.record.issues = phase == .complete ? issues : []
        store.selectedIssueID = job.record.issues.first?.id
        let host = NSHostingView(rootView: ContentView(store: store)
            .environment(\.scenePhase, .active)
            .environment(\.colorScheme, light ? .light : .dark).tint(WorkspaceStyle.action))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        NSApp.appearance = window.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        #expect(host.fittingSize.width <= CGFloat(width))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("feedback-\(width)-\(phase.rawValue).png"))
        window.close()
    }
    // Exercise the animation through the native column host, not just its math.
    job.record.phase = .verifyingWords; job.record.issues = []
    let animatedHost = NSHostingView(rootView: ContentView(store: store)
        .environment(\.scenePhase, .active).environment(\.colorScheme, .dark))
    let animatedWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled], backing: .buffered, defer: false)
    animatedWindow.isReleasedWhenClosed = false
    animatedWindow.appearance = NSAppearance(named: .darkAqua); NSApp.appearance = animatedWindow.appearance
    animatedWindow.contentView = animatedHost; animatedWindow.orderFront(nil)
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    try await Task.sleep(for: .milliseconds(150))
    let split = try #require(descendants(animatedHost).compactMap { $0 as? NSSplitView }.first)
    let inspector = try #require(split.arrangedSubviews.last)
    var frames: [Data] = []
    for index in 0..<3 {
        try await Task.sleep(for: .milliseconds(270))
        let bitmap = try #require(inspector.bitmapImageRepForCachingDisplay(in: inspector.bounds))
        inspector.cacheDisplay(in: inspector.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        frames.append(png)
        try png.write(to: output.appendingPathComponent("loader-live-\(index).png"))
    }
    #expect(frames[0] != frames[1] || frames[1] != frames[2], "Active native inspector must animate, not remain at its initial dot")
    animatedWindow.close()
    for separation in [0.0, 7.0, 14.0] {
        let host = NSHostingView(rootView: LiquidDotsFrame(separation: separation, color: .white)
            .frame(width: 72, height: 36).padding(24).background(.black))
        host.frame = CGRect(x: 0, y: 0, width: 120, height: 84)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("dots-\(Int(separation)).png"))
    }
    await store.finishReadingWrites()
}

@MainActor private final class FeedbackModelModule: ModelModule {
    var readiness = ModelReadiness(required: [])
    var policy: RecognitionPolicy { .init(threshold: 0.5, maximumAttempts: 3) }
    var needsTerminationPreparation: Bool { false }
    func makeSession() throws -> any ModelSession { throw ModelError.unavailable("synthetic fixture") }
    func checkReadiness() async {}
    func prepareForTermination() async {}
}

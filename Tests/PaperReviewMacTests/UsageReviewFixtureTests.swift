import AppKit
import Testing
import PaperReviewCore
@testable import PaperReview

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_USAGE_UI_ROOT"] != nil))
@MainActor func prepareUsageReviewFixture() async throws {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_USAGE_UI_ROOT"]))
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let text = """
    The box of old books are heavy.
    Everyone was there accept Tom.
    Please accept my apology.
    I have lived here since three years.
    I visited Paris last year. I live in London now.
    If I were you, I would wait.
    I do not like tea.
    It was beautifull.
    """
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1400, pixelsHigh: 860,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    graphics.cgContext.translateBy(x: 0, y: 860); graphics.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1400, height: 860).fill()
    for (index, line) in text.components(separatedBy: "\n").enumerated() {
        (line as NSString).draw(at: NSPoint(x: 75, y: 90 + index * 80), withAttributes: [
            .font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = try #require(bitmap.representation(using: .png, properties: [:]))
    let source = root.appendingPathComponent("审核测试-合成.png")
    try image.write(to: source)
    let repository = AssignmentRepository(root: root.appendingPathComponent("assignments"))
    var record = try await repository.importPhoto(source)
    let page = try await PhotoProcessor().prepare(image)
    let transcript = ReadingOrder.transcript(texts: [text], hints: page.hints, regions: page.readingRegions)
    #expect(WordAlignment.inventory(transcript, hints: page.words).unlocatedRanges.isEmpty)
    record.transcript = transcript; record.width = page.width; record.height = page.height
    record.phase = .complete; record.isExample = true
    record.structureVersion = page.scan.version + ":" + PageScaffolding.version
    try await repository.savePage(page, id: record.id)
    try await repository.save(record)
    try record.id.uuidString.write(to: root.appendingPathComponent("assignment-id.txt"), atomically: true, encoding: .utf8)
}

import AppKit
import CoreImage
import ImageIO
import Testing
import Vision
import PaperReviewCore
@testable import PaperReview

@Test func legacyRecordContinuesReviewWithoutRequiringProofreading() {
    var record = AssignmentRecord(title: "legacy", originalFilename: "original.png")
    record.phase = .needsConfirmation
    record.transcript = LineAlignment.fallback("The wether is suny.")
    let original = record.transcript
    record.restoreInterruptedPhase()
    #expect(record.phase == .cancelled)
    #expect(record.failedPhase == .reviewing)
    #expect(record.transcript == original)
    #expect(!record.humanConfirmed)
}

@Test func rejectionCausesSurviveSavingAndReopeningTheAssignment() throws {
    let transcript = LineAlignment.fallback("I goed home.")
    let proposal = IssueProposal(line: 1, quote: "goed", occurrence: 1, kind: .grammar, suggestion: "goed", explanation: "无变化")
    let result = IssueAnchoring.anchor([proposal], to: transcript)
    var record = AssignmentRecord(title: "test", originalFilename: "original.png")
    record.transcript = transcript; record.rejectedIssues = result.rejectedCount; record.reviewRejections = result.rejections
    let restored = try JSONDecoder().decode(AssignmentRecord.self, from: JSONEncoder().encode(record))
    #expect(restored.reviewRejections?.first?.reason == .unchangedSuggestion)
    #expect(restored.reviewRejections?.first?.proposal.quote == "goed")
    #expect(restored.rejectedIssues == 1)
}

@Test @MainActor func naturalTextHeightDoesNotFollowTheHandwritingBox() {
    let text = "I feeled tired but happy."
    func page(height: Double) -> TranscriptPageView {
        let page = TranscriptPageView()
        page.transcript = Transcript(text: text, lines: [.init(id: 1, start: 0, length: text.utf16.count,
            rect: .init(x: 0.05, y: 0.1, width: 0.6, height: height))], isAligned: true)
        return page
    }
    let short = page(height: 0.02).lineLayouts(width: 900, pageHeight: 700)
    let tall = page(height: 0.20).lineLayouts(width: 900, pageHeight: 700)
    #expect(short[0].1.height == tall[0].1.height)
    #expect(TextDrawing.font(zoom: 1).pointSize == 18)
    #expect(TextDrawing.font(zoom: 2).pointSize == 36)
}

@Test @MainActor func narrowPanePreservesPhotographedRowsAndUsesOneLeftEdge() {
    let first = "In the afternoon, i finish my homework. On sunday, I visit my\n"
    let second = "grandparents and help they clean the house."
    let page = TranscriptPageView()
    page.transcript = Transcript(text: first + second, lines: [
        .init(id: 1, start: 0, length: first.utf16.count, rect: .init(x: 0.04, y: 0.3, width: 0.8, height: 0.04)),
        .init(id: 2, start: first.utf16.count, length: second.utf16.count, rect: .init(x: 0.17, y: 0.35, width: 0.6, height: 0.04))
    ], isAligned: true)
    let width = max(280, page.requiredWidth())
    let rows = page.lineLayouts(width: width, pageHeight: 220)
    #expect(width > 280)
    #expect(rows[0].1.height < TextDrawing.font(zoom: 1).pointSize * 2)
    #expect(rows[1].1.minY >= rows[0].1.maxY + 8)
    #expect(rows[0].1.minX == rows[1].1.minX)
    #expect(abs(rows[0].1.minX - width * 0.04) < 0.01)
    #expect(page.requiredHeight(width: width, pageHeight: 220) >= rows.last!.1.maxY)
    #expect(rows.allSatisfy { $0.1.maxX <= width })
}

@Test @MainActor func spreadColumnsKeepSourceRowsAndTheRightPageAtTheTop() {
    let left = "A long left-page sentence that wraps across several display lines.\n"
    let right = "The right page continues here."
    let leftRegion = PageRect(x: 0, y: 0, width: 0.48, height: 1)
    let rightRegion = PageRect(x: 0.48, y: 0, width: 0.52, height: 1)
    let page = TranscriptPageView()
    page.transcript = Transcript(text: left + right, lines: [
        .init(id: 1, start: 0, length: left.utf16.count, rect: .init(x: 0.04, y: 0.5, width: 0.4, height: 0.04), readingRegion: leftRegion),
        .init(id: 2, start: left.utf16.count, length: right.utf16.count, rect: .init(x: 0.52, y: 0.02, width: 0.4, height: 0.04), readingRegion: rightRegion)
    ], isAligned: true)
    let width = max(600, page.requiredWidth())
    let layouts = page.lineLayouts(width: width, pageHeight: 340)
    #expect(layouts[0].1.maxX <= leftRegion.width * width)
    #expect(layouts[1].1.minY < layouts[0].1.minY)
    #expect(layouts[1].1.maxX <= width)
    #expect(layouts[0].1.height < TextDrawing.font(zoom: 1).pointSize * 2)
    #expect(page.requiredHeight(width: width, pageHeight: 340) >= layouts[0].1.maxY)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_LAYOUT_IMAGE"] != nil))
func inspectActualDocumentLayout() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_LAYOUT_IMAGE"])
    let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_LAYOUT_OUTPUT"]))
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let processor = PhotoProcessor()
    let page = try await processor.prepare(data)
    let source = try #require(CGImageSourceCreateWithData(page.source as CFData, nil))
    let cg = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "zh-Hans"]; request.usesLanguageCorrection = false; request.minimumTextHeight = 0.005
    let rectangles = VNDetectRectanglesRequest(); rectangles.maximumObservations = 100
    rectangles.minimumAspectRatio = 0.3; rectangles.maximumAspectRatio = 2
    rectangles.minimumSize = 0.01; rectangles.minimumConfidence = 0.5; rectangles.quadratureTolerance = 25
    try VNImageRequestHandler(cgImage: cg).perform([request, rectangles])
    func box(_ rect: CGRect) -> PageRect { .init(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height) }
    let fragments = (request.results ?? []).compactMap { observation -> TextHint? in
        guard let text = observation.topCandidates(1).first else { return nil }
        return .init(text: text.string, rect: box(observation.boundingBox), confidence: Double(text.confidence))
    }
    struct Layout: Codable { let regions: [PageRect]; let annotations: [PageAnnotation]; let hints: [TextHint]; let fragments: [TextHint]; let rectangles: [PageRect] }
    let result = Layout(regions: page.readingRegions, annotations: page.annotations, hints: page.hints, fragments: fragments,
        rectangles: (rectangles.results ?? []).map { box($0.boundingBox) })
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(to: output.appendingPathComponent("layout.json"), options: .atomic)
    try page.enhanced.write(to: output.appendingPathComponent("enhanced.png"), options: .atomic)
    try page.source.write(to: output.appendingPathComponent("source.png"), options: .atomic)
    try encoder.encode(page.scan).write(to: output.appendingPathComponent("scan.json"), options: .atomic)
    let modelImage = try await processor.recognitionImage(page.enhanced, annotations: page.annotations)
    try modelImage.write(to: output.appendingPathComponent("model-input.png"), options: .atomic)
    for (index, region) in page.readingRegions.enumerated() {
        try await processor.pageCrop(modelImage, region: region).write(to: output.appendingPathComponent("page-\(index + 1).png"), options: .atomic)
        let crop = try await processor.pageCrop(page.source, region: region)
        let source = try #require(CGImageSourceCreateWithData(crop as CFData, nil))
        let cg = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var counts: [String: Int] = [:]
        let curves = RulingGeometry.curves(cg, diagnostics: { counts[$0] = $1 })
        struct Rulings: Codable { let counts: [String: Int]; let curves: [RulingGeometry.Curve] }
        try encoder.encode(Rulings(counts: counts, curves: curves)).write(to: output.appendingPathComponent("rulings-\(index + 1).json"), options: .atomic)
    }
    if ProcessInfo.processInfo.environment["PAPERREVIEW_LAYOUT_OCR"] == "1" {
        let client = ModelClient()
        var texts: [String] = []
        for (index, region) in page.readingRegions.enumerated() {
            let response = try await client.recognize(image: processor.pageCrop(modelImage, region: region), base: "http://127.0.0.1:18499")
            try encoder.encode(["text": response.text]).write(to: output.appendingPathComponent("ocr-\(index + 1).json"), options: .atomic)
            #expect(!response.truncated)
            texts.append(PageScaffolding.bodyText(response.text, annotations: page.annotations))
        }
        let transcript = ReadingOrder.transcript(texts: texts, hints: page.hints, regions: page.readingRegions)
        try encoder.encode(transcript).write(to: output.appendingPathComponent("transcript.json"), options: .atomic)
    }
    #expect(!page.hints.isEmpty)
}

@Test func printedFrameRectificationPreservesInkOutsideTheFrame() throws {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 500,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    let bytes = try #require(bitmap.bitmapData)
    bytes.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    for y in 0..<24 { for x in 0..<24 {
        let offset = y * bitmap.bytesPerRow + x * 4
        bytes[offset + 1] = 0; bytes[offset + 2] = 0
    } }
    let input = CIImage(cgImage: try #require(bitmap.cgImage))
    let quad = PageRectifier.Quad(topLeft: .init(x: 0.15, y: 0.8), topRight: .init(x: 0.85, y: 0.9),
        bottomRight: .init(x: 0.9, y: 0.2), bottomLeft: .init(x: 0.1, y: 0.1))
    let result = try PageRectifier.correct(input, quad: quad, crop: false, method: "printed_frame")
    let context = CIContext()
    let cg = try #require(context.createCGImage(result.image, from: result.image.extent))
    var pixels = [UInt8](repeating: 255, count: cg.width * cg.height * 4)
    let red = try pixels.withUnsafeMutableBytes { buffer in
        let draw = try #require(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        draw.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let values = buffer.bindMemory(to: UInt8.self)
        return stride(from: 0, to: values.count, by: 4).filter { values[$0] > 200 && values[$0 + 1] < 50 && values[$0 + 2] < 50 }.count
    }
    #expect(red > 100)
    #expect(!result.cropped)
    #expect(result.image.extent.minX == 0 && result.image.extent.minY == 0)
}

@Test @MainActor func comparisonModesRetainBothDocumentsAndShareTheSameCoordinates() {
    let view = PairedScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    view.aspect = 0.8; view.text.transcript = LineAlignment.fallback("I goed home.\nMy freind came.")
    for mode in ComparisonMode.allCases {
        view.mode = mode; view.needsLayout = true; view.layoutSubtreeIfNeeded()
        #expect(view.source.frame == view.text.frame)
        #expect(view.source.superview != nil && view.text.superview != nil)
        let visible = view.subviews.compactMap { $0 as? NSScrollView }.filter { !$0.isHidden }
        #expect(visible.count == (mode == .wipe ? 1 : 2))
        if mode == .stacked { #expect(visible[0].frame.maxY < visible[1].frame.minY) }
        if mode == .wipe { #expect(view.source.layer?.mask != nil && view.text.layer?.mask != nil) }
    }
    view.mode = .sideBySide; view.needsLayout = true; view.layoutSubtreeIfNeeded()
    #expect(view.source.layer?.mask == nil && view.text.layer?.mask == nil)
}

@Test @MainActor func magnificationUpdatesTheSharedZoomAndRespectsTheSliderRange() {
    let view = PairedScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    view.text.transcript = LineAlignment.fallback("I goed home.")
    view.layoutSubtreeIfNeeded()
    var received = 0.0
    view.onZoomChange = { received = $0 }
    view.applyZoom(1.5, anchor: NSPoint(x: 100, y: 100))
    #expect(received == 1.5 && view.zoom == 1.5 && view.text.zoom == 1.5)
    #expect(view.source.frame == view.text.frame)
    view.applyZoom(4, anchor: .zero); #expect(view.zoom == 2)
    view.applyZoom(0.2, anchor: .zero); #expect(view.zoom == 0.75)
}

@Test func reopeningKeepsTheSavedPixelsAndTheirGeometryVersionTogether() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-cache-test-\(UUID().uuidString)")
    let repository = AssignmentRepository(root: root)
    let record = AssignmentRecord(title: "cache", originalFilename: "original.png")
    try await repository.save(record)
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let bytes = try #require(bitmap.bitmapData); bytes.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let scan = ScanMetadata(version: "saved-scan-version", perspectiveCorrected: false, originalWidth: 120, originalHeight: 80, corners: [], pages: nil)
    let page = PreparedPage(source: data, enhanced: data, strong: nil, width: 120, height: 80, hints: [], words: [],
        readingRegions: [ReadingOrder.fullPage], annotations: [], cropped: false, scan: scan)
    try await repository.savePage(page, id: record.id)
    let restored = try #require(await repository.prepared(record))
    #expect(restored.scan.version == "saved-scan-version")
    #expect(restored.source == data)
    #expect(restored.width == 120 && restored.height == 80)
    #expect(restored.strong == nil)
    try await repository.archiveBeforeStructureChange(record)
    let history = root.appendingPathComponent(record.id.uuidString).appendingPathComponent("structure-history")
    let archive = try #require(FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil).first)
    #expect(try Data(contentsOf: archive.appendingPathComponent("source.png")) == data)
    let savedRecord = try JSONDecoder().decode(AssignmentRecord.self, from: Data(contentsOf: archive.appendingPathComponent("record.json")))
    #expect(savedRecord.id == record.id)
}

@Test @MainActor func wordHitTestingPreservesTheExactSpanAfterWrapping() throws {
    let text = "The wether is suny and warm."
    let font = TextDrawing.font(zoom: 1)
    let rect = NSRect(x: 16, y: 30, width: 140, height: 100)
    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; style.lineSpacing = font.pointSize * 0.18
    let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: style])
    let manager = NSLayoutManager(); let container = NSTextContainer(size: rect.size); container.lineFragmentPadding = 0
    storage.addLayoutManager(manager); manager.addTextContainer(container); manager.ensureLayout(for: container)
    let range = (text as NSString).range(of: "suny")
    let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    let box = manager.boundingRect(forGlyphRange: glyphs, in: container)
    let point = NSPoint(x: rect.minX + box.midX, y: rect.minY + box.midY)
    let index = try #require(TextDrawing.characterIndex(point, text: text, rect: rect, font: font))
    #expect(NSLocationInRange(index, range))
}

@Test func wordCropPaddingRespectsNeighborBoundary() async throws {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 300,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let words = [
        WordHint(lineID: 1, text: "clean", rect: .init(x: 0.1, y: 0.2, width: 0.1, height: 0.1), confidence: 1),
        WordHint(lineID: 1, text: "the", rect: .init(x: 0.208, y: 0.2, width: 0.1, height: 0.1), confidence: 1)
    ]
    let crop = try await PhotoProcessor().wordCrop(data, hint: words[0], neighbors: words)
    let source = try #require(CGImageSourceCreateWithData(crop as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width <= 113)
    // CGRect.integral rounds both crop edges outward, including FP boundary noise.
    #expect((54...56).contains(image.height))
}

@Test @MainActor func blankWordRegionHasAnExplicitNormalizationError() throws {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    let bytes = try #require(bitmap.bitmapData)
    bytes.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(throws: PhotoError.emptyWordRegion) {
        try TranscriptRenderer.normalizedWordImages(original: data, candidates: ["a", "9"])
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_CROP_CHECKS"] != nil))
func inspectActualWordCrops() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_CROP_CHECKS"])
    let input = URL(fileURLWithPath: path)
    let folder = input.deletingLastPathComponent()
    let checks = try JSONDecoder().decode([WordCheck].self, from: Data(contentsOf: input))
    let output = folder.appendingPathComponent("inspected-word-crops", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let image = try Data(contentsOf: folder.appendingPathComponent("enhanced.png"))
    let processor = PhotoProcessor()
    for check in checks {
        let crop = try await processor.wordCrop(image, hint: check.region.cropHint, neighbors: checks.map { $0.region.cropHint })
        try crop.write(to: output.appendingPathComponent("word-\(check.region.id).png"), options: .atomic)
    }
    #expect(checks.count > 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_REPREPARE_RECORD"] != nil))
func inspectPreparedRowAlignment() async throws {
    let input = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_REPREPARE_RECORD"]))
    let folder = input.deletingLastPathComponent()
    let record = try JSONDecoder().decode(AssignmentRecord.self, from: Data(contentsOf: input))
    let old = try #require(record.transcript)
    let page = try await PhotoProcessor().prepare(Data(contentsOf: folder.appendingPathComponent(record.originalFilename)))
    let transcript = LineAlignment.makeTranscript(text: old.text, hints: page.hints)
    let inventory = WordAlignment.inventory(transcript, hints: page.words)
    struct Result: Codable {
        let transcript: Transcript
        let hints: [TextHint]
        let words: [WordHint]
        let regions: [WordRegion]
        let totalWords: Int
        let locatedWords: Int
    }
    let result = Result(transcript: transcript, hints: page.hints, words: page.words, regions: inventory.regions,
                        totalWords: inventory.transcriptWords, locatedWords: inventory.locatedWords)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(to: folder.appendingPathComponent("row-alignment-probe.json"), options: .atomic)
    #expect(transcript.text == old.text)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_JEV_WORD_PROBE"] != nil)) @MainActor
func compareJevWordNormalization() async throws {
    let input = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_JEV_WORD_PROBE"]))
    let folder = input.deletingLastPathComponent()
    let checks = try JSONDecoder().decode([WordCheck].self, from: Data(contentsOf: input))
    let client = ModelClient()
    struct Result: Codable { let original: String; let isolated: String?; let scores: [String: Double] }
    var results: [Result] = []
    for check in checks where [23, 25, 42, 46].contains(check.region.id) {
        let candidates = Array(Set([check.region.original, check.isolated, check.region.hint].compactMap { $0 })).sorted()
        let crop = try Data(contentsOf: folder.appendingPathComponent("inspected-word-crops/word-\(check.region.id).png"))
        let (source, rendered) = try TranscriptRenderer.normalizedWordImages(original: crop, candidates: candidates)
        try source.write(to: folder.appendingPathComponent("normalized-\(check.region.id)-source.png"))
        var scores: [String: Double] = [:]
        for text in candidates {
            let image = try #require(rendered[text])
            try image.write(to: folder.appendingPathComponent("normalized-\(check.region.id)-\(text).png"))
            scores[text] = try await client.score(original: source, rendered: image, text: text, base: "http://127.0.0.1:18500")
        }
        results.append(Result(original: check.region.original ?? "", isolated: check.isolated, scores: scores))
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(results).write(to: folder.appendingPathComponent("jev-normalized-probe.json"), options: .atomic)
    #expect(results.count == 4)
}

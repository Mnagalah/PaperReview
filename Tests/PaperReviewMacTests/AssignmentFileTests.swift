import AppKit
import Testing
import PaperReviewCore
import PaperReviewLocalModels
@testable import PaperReview

private func importFixture(_ directory: URL, name: String = "photo.png", shade: UInt8 = 255) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    let bytes = try #require(bitmap.bitmapData)
    bytes.initialize(repeating: shade, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    for y in 0..<30 { for x in 0..<40 { bytes[y * bitmap.bytesPerRow + x * 4 + 3] = 255 } }
    let url = directory.appendingPathComponent(name)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    return url
}

@Test func duplicateDetectionUsesContentsNotTheFilenameAndAllowsAnExplicitOverride() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-import-\(UUID())")
    let repository = AssignmentRepository(root: root.appendingPathComponent("assignments"))
    let first = try importFixture(root.appendingPathComponent("source"))
    let renamed = root.appendingPathComponent("source/renamed.png")
    try FileManager.default.copyItem(at: first, to: renamed)
    let original = try await repository.importPhoto(first)
    do {
        _ = try await repository.importPhoto(renamed)
        Issue.record("Same bytes with a different filename must be detected.")
    } catch PhotoImportError.duplicate(let existing) { #expect(existing.id == original.id) }
    #expect(try await repository.load().count == 1)
    let second = try await repository.importPhoto(renamed, allowDuplicate: true)
    #expect(second.id != original.id)
    let different = try importFixture(root.appendingPathComponent("other-source"), shade: 70)
    _ = try await repository.importPhoto(different)
    #expect(try await repository.load().count == 3)
    #expect(try await repository.original(original) == Data(contentsOf: first))
}

@Test func unreadableImagesAreRejectedBeforeAnAssignmentFolderIsCreated() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-invalid-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let invalid = root.appendingPathComponent("broken.png")
    try Data("not an image".utf8).write(to: invalid)
    let repository = AssignmentRepository(root: root.appendingPathComponent("assignments"))
    await #expect(throws: PhotoImportError.self) { try await repository.importPhoto(invalid) }
    #expect(try await repository.load().isEmpty)
    #expect(try Data(contentsOf: invalid) == Data("not an image".utf8))
}

@Test func trashIsRecoverablePreservesTheSourceAndRejectsLateSaves() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-trash-\(UUID())")
    let directory = root.appendingPathComponent("assignments")
    let repository = AssignmentRepository(root: directory)
    let source = try importFixture(root.appendingPathComponent("source"))
    let record = try await repository.importPhoto(source)
    let owned = directory.appendingPathComponent(record.id.uuidString)
    let destination = try #require(await repository.trash(record))
    // Always put our own fixture back. Never enumerate or remove other Trash items.
    defer { try? FileManager.default.moveItem(at: destination, to: owned) }
    #expect(!FileManager.default.fileExists(atPath: owned.path))
    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("record.json").path))
    #expect(try Data(contentsOf: source) == Data(contentsOf: destination.appendingPathComponent(record.originalFilename)))
    await #expect(throws: AssignmentFileError.self) { try await repository.save(record) }
    #expect(!FileManager.default.fileExists(atPath: owned.path))
}

@Test @MainActor func sidebarDeletionRejectsRunningJobsAndReservesQueuedWork() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-store-trash-\(UUID())")
    let directory = root.appendingPathComponent("assignments")
    let repository = AssignmentRepository(root: directory)
    let source = try importFixture(root.appendingPathComponent("source"))
    let job = Assignment(record: try await repository.importPhoto(source))
    let store = WorkspaceStore(models: LocalModelModule(), dataRoot: directory)
    store.assignments = [job]; store.selectedID = job.id
    for phase in [PipelinePhase.preparing, .recognizing, .verifyingWords, .scoring, .reviewing] {
        job.record.phase = phase
        #expect(!store.canDelete(job))
    }
    job.record.phase = .queued
    #expect(store.canDelete(job))
    let destination = try #require(await store.trash(job))
    defer { try? FileManager.default.moveItem(at: destination, to: directory.appendingPathComponent(job.id.uuidString)) }
    #expect(store.assignments.isEmpty && store.selectedID == nil)
    #expect(store.activeID == nil && store.globalError == nil)
    #expect(FileManager.default.fileExists(atPath: source.path))
    store.retry(job)
    #expect(store.activeID == nil)
}

@Test @MainActor func readabilityWarningUsesTheCurrentPhotoEvidenceEvenWhenReviewFails() {
    let transcript = LineAlignment.fallback(Array(repeating: "suny", count: 10).joined(separator: " "))
    let hints = (0..<10).map { WordHint(lineID: 1, text: "suny",
        rect: .init(x: 0.05 + Double($0) * 0.08, y: 0.1, width: 0.06, height: 0.1), confidence: 1) }
    let checks = WordAlignment.inventory(transcript, hints: hints).regions.map {
        WordCheck(region: $0, isolated: nil, sourceReading: nil, sourceChecked: true)
    }
    let evidence = ReadabilityEvidence(checks: checks, totalRegions: 10)
    var record = AssignmentRecord(title: "readability", originalFilename: "original.png")
    record.phase = .failed; record.failedPhase = .reviewing; record.transcript = transcript
    let job = Assignment(record: record)
    let page = PreparedPage(source: Data(), enhanced: Data(), strong: nil, width: 400, height: 300,
        hints: [], words: [], readingRegions: [ReadingOrder.fullPage], annotations: [], cropped: false,
        scan: ScanMetadata(version: PhotoProcessor.version, perspectiveCorrected: false, originalWidth: 400,
            originalHeight: 300, corners: [], pages: nil))
    job.setPage(page)
    job.record.candidates = [OCRCandidate(attempt: 1, transcript: transcript, score: 0.9,
        scoredSourceVersion: PhotoProcessor.version, readability: evidence)]
    #expect(job.hasPoorReadability)
    job.record.phase = .recognizing
    #expect(!job.hasPoorReadability)
    job.record.phase = .complete
    job.record.candidates = [OCRCandidate(attempt: 1, transcript: transcript, score: 0.01)]
    #expect(!job.hasPoorReadability)
    job.record.candidates = [OCRCandidate(attempt: 1, transcript: transcript, score: 0.01,
        scoredSourceVersion: "old-scan", readability: evidence)]
    #expect(!job.hasPoorReadability)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_TRASH_PROBE_ROOT"] != nil))
func inspectWorkspaceTrashRecovery() async throws {
    let base = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_TRASH_PROBE_ROOT"]))
        .appendingPathComponent("trash-probe-\(UUID())")
    let root = base.appendingPathComponent("assignments")
    let repository = AssignmentRepository(root: root)
    let source = try importFixture(base.appendingPathComponent("source"))
    let record = try await repository.importPhoto(source)
    let destination = try #require(await repository.trash(record))
    let evidence = ["id": record.id.uuidString, "destination": destination.path, "source": source.path,
                    "restore": root.appendingPathComponent(record.id.uuidString).path]
    try JSONEncoder().encode(evidence).write(to: base.appendingPathComponent("trash-location.json"))
    print("Workspace test Trash destination: \(destination.path)")
    defer { try? FileManager.default.moveItem(at: destination, to: root.appendingPathComponent(record.id.uuidString)) }
    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("record.json").path))
    #expect(try Data(contentsOf: destination.appendingPathComponent(record.originalFilename)) == Data(contentsOf: source))
}

@Test @MainActor func recoveredPhotoPreparationContinuesAtOCRWithoutReimporting() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-prepared-recovery-\(UUID())")
    let repository = AssignmentRepository(root: root.appendingPathComponent("assignments"))
    let source = try importFixture(root.appendingPathComponent("source"))
    var record = try await repository.importPhoto(source)
    record.phase = .failed; record.failedPhase = .preparing; record.error = "previous system image request failed"
    record.structureVersion = PhotoProcessor.version + ":" + PageScaffolding.version
    try await repository.save(record)
    let data = try Data(contentsOf: source)
    let page = PreparedPage(source: data, enhanced: data, strong: nil, width: 40, height: 30,
        hints: [], words: [], readingRegions: [ReadingOrder.fullPage], annotations: [], cropped: false,
        scan: ScanMetadata(version: PhotoProcessor.version, perspectiveCorrected: false,
            originalWidth: 40, originalHeight: 30, corners: [], pages: nil))
    try await repository.savePage(page, id: record.id)
    let store = WorkspaceStore(models: LocalModelModule(), dataRoot: root.appendingPathComponent("assignments"))
    await store.restore()
    let job = try #require(store.selected)
    #expect(job.id == record.id && job.page != nil)
    #expect(job.record.phase == .cancelled && job.record.failedPhase == .recognizing)
    #expect(job.record.error == nil && !job.record.humanConfirmed)
    #expect(store.activeID == nil)
    let saved = try #require(await repository.load().first)
    #expect(saved.phase == .cancelled && saved.failedPhase == .recognizing && saved.error == nil)
}

@Test @MainActor func partialGeometryRecoveryPreservesTextReviewAndUncertaintyWithoutCallingOCR() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReview-partial-\(UUID())")
    let directory = root.appendingPathComponent("assignments")
    let repository = AssignmentRepository(root: directory)
    let source = try importFixture(root.appendingPathComponent("source"))
    let rows = ["My freind likes films.", "A rabbit and a fox are friends.", "They help everyone in the city.", "They appear."]
    let transcript = LineAlignment.fallback(rows.joined(separator: "\n"))
    let hints = (Array(rows.prefix(3)) + ["zzzz qqqq xxxx"]).enumerated().map { i, text in
        TextHint(text: text, rect: .init(x: 0.12, y: 0.18 + Double(i) * 0.17, width: 0.7, height: 0.07))
    }
    let words = [WordHint(lineID: 1, text: "freind", rect: .init(x: 0.2, y: 0.18, width: 0.1, height: 0.07), confidence: 1)]
    var record = try await repository.importPhoto(source)
    record.phase = .complete; record.transcript = transcript; record.attempt = 1
    record.structureVersion = PhotoProcessor.version + ":" + PageScaffolding.version
    let evidence = ReadabilityEvidence(checks: [], totalRegions: 0)
    record.candidates = [OCRCandidate(attempt: 1, transcript: transcript, score: 0.23,
        scoredSourceVersion: PhotoProcessor.version, readability: evidence)]
    let issue = ReviewIssue(revision: transcript.revision, lineID: 1, start: 3, length: 6,
        quote: "freind", kind: .spelling, suggestion: "friend", explanation: "拼写顺序应为ie。")
    record.deferredReviewIssues = [issue]
    try await repository.save(record)
    let data = try Data(contentsOf: source)
    let page = PreparedPage(source: data, enhanced: data, strong: nil, width: 40, height: 30,
        hints: hints, words: words, readingRegions: [ReadingOrder.fullPage], annotations: [], cropped: false,
        scan: ScanMetadata(version: PhotoProcessor.version, perspectiveCorrected: false,
            originalWidth: 40, originalHeight: 30, corners: [], pages: nil))
    try await repository.savePage(page, id: record.id)
    let store = WorkspaceStore(models: LocalModelModule(), dataRoot: directory)
    await store.restore()
    let job = try #require(store.selected)
    #expect(job.record.transcript?.text == transcript.text && job.record.transcript?.revision == transcript.revision)
    #expect(job.record.transcript?.lines.map(\.hasGeometry) == [true, true, true, false])
    #expect(job.record.phase == .complete && store.activeID == nil && job.record.attempt == 1)
    #expect(job.record.candidates.first?.score == 0.23 && job.record.candidates.first?.readability == evidence)
    #expect(job.record.deferredReviewIssues?.first?.id == issue.id)
    // Newly located text was unlocated before. Geometry recovery does not turn
    // it into an independently verified spelling or release deferred advice.
    let recovered = try #require(job.wordRegions.first { $0.original == "freind" })
    #expect(job.uncertainWordRects.contains(recovered.rect))
    let history = directory.appendingPathComponent(record.id.uuidString).appendingPathComponent("structure-history")
    let archive = try #require(FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil).first)
    let old = try JSONDecoder().decode(AssignmentRecord.self, from: Data(contentsOf: archive.appendingPathComponent("record.json")))
    #expect(old.transcript == transcript && old.deferredReviewIssues?.first?.id == issue.id)
}

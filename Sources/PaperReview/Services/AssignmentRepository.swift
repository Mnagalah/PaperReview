import Foundation
import ImageIO
import PaperReviewCore

nonisolated enum PhotoImportError: LocalizedError {
    case unreadable
    case duplicate(AssignmentRecord)
    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取这张照片。请使用完整的 JPEG、PNG、HEIC 或 TIFF 图片。"
        case .duplicate(let record): "这张照片已导入为“\(record.title)”。"
        }
    }
}

nonisolated enum AssignmentFileError: LocalizedError {
    case removed, busy
    var errorDescription: String? {
        switch self {
        case .removed: "这份作业已移除，请重新选择作业。"
        case .busy: "这份作业正在处理，请暂停后再删除。"
        }
    }
}

actor AssignmentRepository {
    let root: URL
    private var trashedIDs: Set<UUID> = []
    init(root: URL) { self.root = root }
    func load() throws -> [AssignmentRecord] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return directories.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("record.json")) else { return nil }
            return try? JSONDecoder().decode(AssignmentRecord.self, from: data)
        }.sorted { $0.createdAt < $1.createdAt }
    }
    func importPhoto(_ url: URL, allowDuplicate: Bool = false) throws -> AssignmentRecord {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true,
              ["jpg", "jpeg", "png", "heic", "tif", "tiff"].contains(url.pathExtension.lowercased()),
              let input = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceCreateThumbnailAtIndex(input, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256
              ] as CFDictionary) != nil else { throw PhotoImportError.unreadable }
        if !allowDuplicate {
            for existing in try load() {
                let original = folder(existing.id).appendingPathComponent(existing.originalFilename)
                let size = try? original.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if size == properties.fileSize && FileManager.default.contentsEqual(atPath: url.path, andPath: original.path) {
                    throw PhotoImportError.duplicate(existing)
                }
            }
        }
        var record = AssignmentRecord(title: url.deletingPathExtension().lastPathComponent, originalFilename: "original.\(url.pathExtension.lowercased())")
        record.importedFilename = url.lastPathComponent
        let directory = folder(record.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(record.originalFilename))
            try save(record)
        } catch {
            // Roll back only the new UUID folder owned by this failed import.
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return record
    }
    /// Only the app-owned copy moves to Trash. The caller reserves queued work
    /// before awaiting this actor so it cannot start while being removed.
    @discardableResult func trash(_ record: AssignmentRecord) throws -> URL? {
        guard !record.phase.isRunning else { throw AssignmentFileError.busy }
        try requirePresent(record.id)
        let directory = folder(record.id)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("record.json").path) else {
            throw AssignmentFileError.removed
        }
        var result: NSURL?
        try FileManager.default.trashItem(at: directory, resultingItemURL: &result)
        trashedIDs.insert(record.id)
        return result as URL?
    }
    func original(_ record: AssignmentRecord) throws -> Data {
        try Data(contentsOf: folder(record.id).appendingPathComponent(record.originalFilename))
    }
    func originalURL(_ record: AssignmentRecord) -> URL { folder(record.id).appendingPathComponent(record.originalFilename) }
    /// A saved transcript and its source geometry are one version. Do not silently
    /// replace the photo with newly warped pixels while retaining old word boxes.
    func prepared(_ record: AssignmentRecord) throws -> PreparedPage? {
        let directory = folder(record.id)
        let names = ["source.png", "enhanced.png", "scan.json", "line-geometry.json", "word-geometry.json"]
        guard names.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else { return nil }
        func data(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
        let source = try data("source.png")
        guard let input = CGImageSourceCreateWithData(source as CFData, nil), let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else { throw PhotoError.unreadable }
        let decoder = JSONDecoder()
        let scan = try decoder.decode(ScanMetadata.self, from: data("scan.json"))
        let hints = try decoder.decode([TextHint].self, from: data("line-geometry.json"))
        let words = try decoder.decode([WordHint].self, from: data("word-geometry.json"))
        let regions = FileManager.default.fileExists(atPath: directory.appendingPathComponent("reading-order.json").path)
            ? try decoder.decode([PageRect].self, from: data("reading-order.json")) : [ReadingOrder.fullPage]
        let annotations = FileManager.default.fileExists(atPath: directory.appendingPathComponent("page-annotations.json").path)
            ? try decoder.decode([PageAnnotation].self, from: data("page-annotations.json")) : []
        let strong = FileManager.default.fileExists(atPath: directory.appendingPathComponent("strong.png").path) ? try data("strong.png") : nil
        return PreparedPage(source: source, enhanced: try data("enhanced.png"), strong: strong,
            width: image.width, height: image.height, hints: hints, words: words, readingRegions: regions, annotations: annotations,
            cropped: scan.pages?.contains(where: { $0.cropped }) ?? scan.perspectiveCorrected, scan: scan)
    }
    func save(_ record: AssignmentRecord) throws {
        try requirePresent(record.id)
        let directory = folder(record.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: directory.appendingPathComponent("record.json"), options: .atomic)
    }
    func savePage(_ page: PreparedPage, id: UUID) throws {
        try requirePresent(id)
        let directory = folder(id)
        try JSONEncoder().encode(page.words).write(to: directory.appendingPathComponent("word-geometry.json"), options: .atomic)
        try JSONEncoder().encode(page.hints).write(to: directory.appendingPathComponent("line-geometry.json"), options: .atomic)
        try JSONEncoder().encode(page.readingRegions).write(to: directory.appendingPathComponent("reading-order.json"), options: .atomic)
        try JSONEncoder().encode(page.annotations).write(to: directory.appendingPathComponent("page-annotations.json"), options: .atomic)
        try page.source.write(to: directory.appendingPathComponent("source.png"), options: .atomic)
        try page.enhanced.write(to: directory.appendingPathComponent("enhanced.png"), options: .atomic)
        if let strong = page.strong { try strong.write(to: directory.appendingPathComponent("strong.png"), options: .atomic) }
        try JSONEncoder().encode(page.scan).write(to: directory.appendingPathComponent("scan.json"), options: .atomic)
    }
    func saveWordChecks(_ checks: [PaperReviewCore.WordCheck], attempt: Int, id: UUID) throws {
        try requirePresent(id)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(checks).write(to: folder(id).appendingPathComponent("word-check-\(attempt).json"), options: .atomic)
    }
    func wordChecks(attempt: Int, id: UUID) throws -> [WordCheck] {
        try requirePresent(id)
        let path = folder(id).appendingPathComponent("word-check-\(attempt).json")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try JSONDecoder().decode([WordCheck].self, from: Data(contentsOf: path))
    }
    func savePageReading(_ response: OCRResponse, region: PageRect, page: Int, attempt: Int, id: UUID) throws {
        try requirePresent(id)
        struct Reading: Codable { let region: PageRect; let page: Int; let text: String; let truncated: Bool }
        let reading = Reading(region: region, page: page, text: response.text, truncated: response.truncated)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(reading).write(to: folder(id).appendingPathComponent("page-ocr-\(attempt)-\(page).json"), options: .atomic)
    }
    func archiveBeforeStructureChange(_ record: AssignmentRecord) throws {
        try requirePresent(record.id)
        let directory = folder(record.id).appendingPathComponent("structure-history", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: directory.appendingPathComponent("record.json"), options: .atomic)
        var files = ["source.png", "enhanced.png", "strong.png", "scan.json", "line-geometry.json", "word-geometry.json", "reading-order.json", "page-annotations.json"]
        for attempt in Set(record.candidates.map(\.attempt)) {
            files += ["word-check-\(attempt).json", "text-structure-\(attempt).json", "candidate-\(attempt)-render.png"]
        }
        for name in files {
            let source = folder(record.id).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name)) }
        }
    }
    func saveTextStructure(_ transcript: Transcript, checks: [WordCheck], page: PreparedPage, attempt: Int, id: UUID,
                           recognitionSourceVersion: String? = nil) throws {
        try requirePresent(id)
        struct Word: Codable {
            let text: String; let start: Int; let length: Int; let rect: PageRect?; let status: String
            let enhancedReading: String?; let sourceReading: String?; let evidence: String?
        }
        struct Line: Codable {
            let id: Int; let text: String; let start: Int; let length: Int; let rect: PageRect?; let words: [Word]
        }
        struct Page: Codable { let index: Int; let region: PageRect; let lines: [Line]; let unanchoredWords: [WordCheck] }
        struct Document: Codable {
            let version: String; let revision: UUID; let scanVersion: String; let recognitionSourceVersion: String
            let text: String; let annotations: [PageAnnotation]; let pages: [Page]
        }
        let inventory = WordAlignment.inventory(transcript, hints: page.words)
        let ns = transcript.text as NSString
        let pages = page.readingRegions.enumerated().map { index, region in
            let lines = transcript.lines.filter { ($0.readingRegion ?? ReadingOrder.fullPage) == region }.map { line in
                var words: [Word] = inventory.regions.filter { $0.lineID == line.id && $0.range != nil }.compactMap { word in
                    guard let range = word.range else { return nil }
                    let check = checks.first { $0.region.rect == word.rect }
                    return Word(text: ns.substring(with: range), start: range.location, length: range.length, rect: word.rect,
                        status: check.map { $0.unresolved ? "disputed" : "consistent" } ?? (recognitionSourceVersion == nil ? "pending" : "not_rechecked_after_scan"),
                        enhancedReading: check?.isolated, sourceReading: check?.sourceReading, evidence: check?.evidence)
                }
                words += inventory.unlocatedRanges.filter { NSIntersectionRange($0, line.range).length > 0 }.map { range in
                    Word(text: ns.substring(with: range), start: range.location, length: range.length, rect: nil,
                        status: "unlocated", enhancedReading: nil, sourceReading: nil, evidence: nil)
                }
                return Line(id: line.id, text: transcript.text(in: line), start: line.start, length: line.length,
                    rect: transcript.isAligned && line.hasGeometry ? line.rect : nil, words: words.sorted { $0.start < $1.start })
            }
            let unanchored = checks.filter { check in
                check.region.range == nil && ReadingOrder.contains(region, hint: .init(text: "", rect: check.region.rect))
            }
            return Page(index: index + 1, region: region, lines: lines, unanchoredWords: unanchored)
        }
        let document = Document(version: "page-line-word-v1", revision: transcript.revision,
            scanVersion: page.scan.version, recognitionSourceVersion: recognitionSourceVersion ?? page.scan.version, text: transcript.text,
            annotations: page.annotations, pages: pages)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: folder(id).appendingPathComponent("text-structure-\(attempt).json"), options: .atomic)
    }
    func saveReview(_ result: ReviewResult, transcript: Transcript, deferred: [ReviewIssue], id: UUID, source: String = "model") throws {
        try requirePresent(id)
        struct Audit: Codable {
            let source: String
            let createdAt: Date
            let revision: UUID
            let proposalsAccepted: [ReviewIssue]
            let rejections: [RejectedReviewIssue]
            let deferredForOCR: [ReviewIssue]
            let recoveredOccurrences: [IssueProposal]
            let recoveredLines: [IssueProposal]
            let modelEvidence: ReviewModelEvidence?
        }
        let directory = folder(id).appendingPathComponent("review-history", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audit = Audit(source: source, createdAt: Date(), revision: transcript.revision, proposalsAccepted: result.issues,
                          rejections: result.rejections, deferredForOCR: deferred,
                          recoveredOccurrences: result.recoveredOccurrences, recoveredLines: result.recoveredLines, modelEvidence: result.modelEvidence)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(audit).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"), options: .atomic)
    }
    func saveRendered(_ data: Data, attempt: Int, id: UUID) throws {
        try requirePresent(id)
        try data.write(to: folder(id).appendingPathComponent("candidate-\(attempt)-render.png"), options: .atomic)
    }
    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func requirePresent(_ id: UUID) throws {
        guard !trashedIDs.contains(id) else { throw AssignmentFileError.removed }
    }
}

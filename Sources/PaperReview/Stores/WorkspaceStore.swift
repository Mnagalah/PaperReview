import AppKit
import Observation
import UniformTypeIdentifiers
import PaperReviewCore

struct DuplicatePhoto: Identifiable {
    let id = UUID()
    let url: URL
    let existingID: UUID
    let existingTitle: String
}

@Observable final class WorkspaceStore {
    var assignments: [Assignment] = []
    var selectedID: UUID?
    var selectedIssueID: UUID?
    var showingSettings = false
    var globalError: String?
    var duplicatePhotos: [DuplicatePhoto] = []
    let models: any ModelModule
    private(set) var activeID: UUID?
    private var task: Task<Void, Never>?
    private var pending: [UUID: PipelinePhase] = [:]
    private var restarting: Set<UUID> = []
    private var deleting: Set<UUID> = []
    private var hydrating: Set<UUID> = []
    @ObservationIgnored private var photoPanel: NSOpenPanel?
    private var restored = false
    private struct CachedReading { let text: String? }
    private var wordReadings: [String: CachedReading] = [:]
    private var wordScores: [String: Double] = [:]
    let repository: AssignmentRepository
    @ObservationIgnored var readingSaves: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var reviewSaves: [UUID: Task<Void, Never>] = [:]
    private let processor = PhotoProcessor()
    private func structureVersion(_ page: PreparedPage) -> String { page.scan.version + ":" + PageScaffolding.version }
    var selected: Assignment? { assignments.first { $0.id == selectedID } }
    var allModelsReady: Bool { models.readiness.isReady }

    init(models: any ModelModule, dataRoot: URL? = nil) {
        self.models = models
        let arguments = ProcessInfo.processInfo.arguments
        let root: URL
        if let dataRoot { root = dataRoot }
        else if let index = arguments.firstIndex(of: "--data-root"), arguments.count > index + 1 {
            root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PaperReview/Assignments", isDirectory: true)
        }
        repository = AssignmentRepository(root: root)
    }

    func restore() async {
        guard !restored else { return }; restored = true
        do {
            assignments = try await repository.load().map { record in
                var record = record
                record.restoreInterruptedPhase()
                return Assignment(record: record)
            }
            selectedID = assignments.last?.id
            for job in assignments { job.reading = (try? await repository.readingState(id: job.id)) ?? ReadingState() }
            selectedIssueID = selected?.reading.selectedIssueID ?? selected?.record.pendingIssues.first?.id
            if let selected { await hydrate(selected) }
        } catch { globalError = "无法读取本机作业记录：\(error.localizedDescription)" }
        await checkModels()
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--import"), args.count > index + 1 {
            await importURLs([URL(fileURLWithPath: args[index + 1])])
        }
    }

    func select(_ id: UUID?) {
        if let selected { selected.reading.selectedIssueID = selectedIssueID; saveReading(selected) }
        selectedID = id
        selectedIssueID = selected?.reading.selectedIssueID ?? selected?.record.pendingIssues.first?.id
        guard let job = selected else { return }
        Task { await hydrate(job) }
    }

    func importPanel() {
        NSApp.activate(ignoringOtherApps: true)
        if let photoPanel { photoPanel.makeKeyAndOrderFront(nil); return }
        // Resolve the owner before creating another window. This also handles
        // invoking the action while the workspace is not the key window.
        let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let panel = NSOpenPanel()
        photoPanel = panel
        panel.title = "导入英语作文照片"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            self.photoPanel = nil
            guard response == .OK else { return }
            let urls = panel.urls
            Task { await self.importURLs(urls) }
        }
        if let window = parentWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else { panel.begin(completionHandler: completion) }
    }

    func importURLs(_ urls: [URL], allowDuplicate: Bool = false) async {
        defer { pump() }
        var failures: [String] = []
        for url in urls {
            do {
                let record = try await repository.importPhoto(url, allowDuplicate: allowDuplicate)
                let job = Assignment(record: record)
                assignments.append(job)
                selectedID = job.id; selectedIssueID = nil
            } catch PhotoImportError.duplicate(let existing) {
                if !duplicatePhotos.contains(where: { $0.url == url && $0.existingID == existing.id }) {
                    duplicatePhotos.append(.init(url: url, existingID: existing.id, existingTitle: existing.title))
                }
            } catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        if !failures.isEmpty { globalError = failures.joined(separator: "\n") }
    }

    func importDuplicates() {
        let urls = duplicatePhotos.map(\.url)
        duplicatePhotos = []
        Task { await importURLs(urls, allowDuplicate: true) }
    }

    func showExisting(_ duplicate: DuplicatePhoto) {
        duplicatePhotos = []
        select(duplicate.existingID)
    }

    func canDelete(_ job: Assignment) -> Bool {
        assignments.contains { $0.id == job.id } && activeID != job.id && !job.record.phase.isRunning
            && !restarting.contains(job.id) && !deleting.contains(job.id) && !hydrating.contains(job.id) && !job.savingReview && job.reviewSaveError == nil
    }

    @discardableResult func trash(_ job: Assignment) async -> URL? {
        guard canDelete(job) else {
            globalError = "这份作业正在处理或加载，请暂停或稍后再删除。"; return nil
        }
        // Reserve before the first await: pump cannot begin this queued job.
        deleting.insert(job.id)
        defer { deleting.remove(job.id); pump() }
        do {
            let destination = try await repository.trash(job.record)
            pending.removeValue(forKey: job.id)
            guard let index = assignments.firstIndex(where: { $0.id == job.id }) else { return destination }
            assignments.remove(at: index)
            if selectedID == job.id {
                select(assignments.isEmpty ? nil : assignments[min(index, assignments.count - 1)].id)
            }
            return destination
        } catch { globalError = "未能移到废纸篓，作业仍保留：\(error.localizedDescription)"; return nil }
    }

    private func pump() {
        guard task == nil, let job = assignments.first(where: {
            $0.record.phase == .queued && !deleting.contains($0.id) && !restarting.contains($0.id) && !hydrating.contains($0.id)
        }) else { return }
        let resume = pending.removeValue(forKey: job.id) ?? .recognizing
        activeID = job.id
        task = Task {
            await process(job, resume: resume)
            activeID = nil; task = nil
            pump()
        }
    }

    private func hydrate(_ job: Assignment) async {
        guard job.page == nil, activeID != job.id, !deleting.contains(job.id), !hydrating.contains(job.id),
              assignments.contains(where: { $0.id == job.id }) else { return }
        hydrating.insert(job.id)
        defer { hydrating.remove(job.id); pump() }
        do {
            let page: PreparedPage
            if let saved = try await repository.prepared(job.record) {
                if saved.scan.version != PhotoProcessor.version && activeID != job.id {
                    let refreshed = try await processor.prepare(repository.original(job.record))
                    page = try await refreshGeometry(job, from: saved, to: refreshed) ? refreshed : saved
                } else { page = saved }
            }
            else { page = try await processor.prepare(repository.original(job.record)) }
            try Task.checkCancellation()
            job.setPage(page)
            try await adoptStructure(page, for: job)
            if let old = job.record.transcript, !old.isAligned, page.readingRegions.count == 1,
               LineAlignment.makeTranscript(text: old.text, hints: page.hints).isAligned {
                // Reuse the archived, text-preserving geometry-upgrade path.
                // Jev's fixed renderer uses text only; no new score is implied.
                _ = try await refreshGeometry(job, from: page, to: page)
            }
            if job.record.phase == .failed && job.record.failedPhase == .preparing {
                // The same original has now been prepared and saved successfully.
                // Do not leave a stale photo failure over a usable scan, or require
                // another import. Resume at OCR after the teacher restarts work.
                try await repository.savePage(page, id: job.id)
                job.record.phase = .cancelled; job.record.failedPhase = .recognizing
                job.record.error = nil
                try await repository.save(job.record)
            }
            if let transcript = job.record.transcript {
                let relocated = IssueAnchoring.relocatingUniqueWordQuotes(job.record.issues, in: transcript)
                if relocated != job.record.issues {
                    job.record.issues = relocated
                    try await repository.save(job.record)
                }
            }
        } catch { job.record.error = "无法加载原片：\(error.localizedDescription)" }
    }

    private func prepare(_ job: Assignment) async throws -> PreparedPage {
        if let page = job.page {
            try await repository.savePage(page, id: job.id)
            return page
        }
        job.record.phase = .preparing
        let data = try await repository.original(job.record)
        if let preview = NSImage(data: data) {
            job.sourceImage = preview; job.enhancedImage = preview
            job.record.width = max(1, Int(preview.size.width)); job.record.height = max(1, Int(preview.size.height))
        }
        let page = try await processor.prepare(data)
        try Task.checkCancellation()
        job.setPage(page)
        job.record.pageAnnotations = page.annotations
        job.record.structureVersion = structureVersion(page)
        try await repository.savePage(page, id: job.id)
        return page
    }

    /// Geometry upgrades retain the text revision; no OCR/Jev run is implied.
    private func refreshGeometry(_ job: Assignment, from oldPage: PreparedPage, to newPage: PreparedPage) async throws -> Bool {
        guard !job.record.phase.isRunning else { return false }
        guard let old = job.record.transcript else { return true }
        let sections = ReadingOrder.pageTranscripts(old)
        guard sections.count == newPage.readingRegions.count else { return false }
        var texts = sections.map { $0.transcript.text }
        for index in texts.indices.dropLast() {
            guard texts[index].last == "\n" else { return false }
            texts[index].removeLast()
        }
        let aligned = ReadingOrder.transcript(texts: texts, hints: newPage.hints, regions: newPage.readingRegions)
        guard aligned.text == old.text else { return false }
        let transcript = Transcript(text: old.text, revision: old.revision, lines: aligned.lines, isAligned: aligned.isAligned)
        let prior = job.record.candidates.first { $0.transcript.revision == old.revision }
        let oldInventory = WordAlignment.inventory(old, hints: oldPage.words)
        let uncertainRanges = oldInventory.unlocatedRanges + oldInventory.regions
            .filter { prior?.uncertainWordRects?.contains($0.rect) == true }.compactMap(\.range)
        let inventory = WordAlignment.inventory(transcript, hints: newPage.words)
        let uncertain = inventory.regions.filter { word in
            guard let range = word.range else { return true }
            return uncertainRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }
        var record = job.record
        record.transcript = transcript
        func relocated(_ issue: ReviewIssue) -> ReviewIssue {
            let line = transcript.lines.first { NSIntersectionRange($0.range, issue.range).length > 0 }
            return ReviewIssue(id: issue.id, revision: issue.revision, lineID: line?.id ?? issue.lineID,
                start: issue.start, length: issue.length, quote: issue.quote, kind: issue.kind,
                suggestion: issue.suggestion, explanation: issue.explanation, dismissed: issue.dismissed)
        }
        record.issues = record.issues.map(relocated)
        record.deferredReviewIssues = record.deferredReviewIssues?.map(relocated)
        if let prior, let index = record.candidates.firstIndex(where: { $0.id == prior.id }) {
            record.candidates[index] = OCRCandidate(attempt: prior.attempt, transcript: transcript, score: prior.score,
                rawText: prior.rawText, literalRepairs: prior.literalRepairs, wordVerification: prior.wordVerification,
                uncertainLineIDs: Array(Set(uncertain.map(\.lineID))).sorted(), uncertainWordRects: uncertain.map(\.rect),
                scoredSourceVersion: prior.scoredSourceVersion ?? oldPage.scan.version, readability: prior.readability)
        }
        record.width = newPage.width; record.height = newPage.height
        try await repository.archiveBeforeStructureChange(job.record)
        guard job.record.transcript?.revision == old.revision, !job.record.phase.isRunning else { return false }
        try await repository.savePage(newPage, id: job.id)
        try await repository.saveTextStructure(transcript, checks: [], page: newPage, attempt: record.attempt, id: job.id,
            recognitionSourceVersion: prior?.scoredSourceVersion ?? oldPage.scan.version)
        try await repository.save(record)
        job.record = record
        return true
    }

    private func adoptStructure(_ page: PreparedPage, for job: Assignment) async throws {
        guard job.record.structureVersion != structureVersion(page), activeID != job.id else { return }
        var updated = job.record
        updated.structureVersion = structureVersion(page); updated.pageAnnotations = page.annotations
        var continuation: PipelinePhase = .reviewing
        if !updated.humanConfirmed, let old = updated.transcript {
            let body = PageScaffolding.bodyText(old.text, annotations: page.annotations)
            let needsPageOrder = page.readingRegions.count > 1 && old.lines.allSatisfy { $0.readingRegion == nil }
            if body != old.text || needsPageOrder {
                try await repository.archiveBeforeStructureChange(job.record)
                if needsPageOrder {
                    // Do not guess page boundaries by matching common words in an
                    // old, wrongly ordered response. Re-read the actual page crops.
                    updated.candidates = []; updated.attempt = 0
                    continuation = .recognizing
                } else {
                    let transcript = ReadingOrder.transcript(texts: [body], hints: page.hints, regions: page.readingRegions)
                    let uncertain = job.uncertainWordRects
                    updated.transcript = transcript
                    updated.candidates = [OCRCandidate(attempt: max(1, updated.attempt), transcript: transcript,
                        rawText: old.text, uncertainWordRects: uncertain)]
                }
                updated.issues = []; updated.rejectedIssues = 0; updated.reviewRejections = nil; updated.deferredReviewIssues = nil
                updated.wordChecksCompleted = nil; updated.wordChecksTotal = nil
                updated.failedPhase = continuation
                if updated.phase == .complete || updated.phase == .needsConfirmation { updated.phase = .queued }
            }
        }
        try await repository.savePage(page, id: job.id)
        try await repository.save(updated)
        job.record = updated
        if updated.phase == .queued && updated.transcript != nil {
            pending[job.id] = continuation; pump()
        }
    }

    private func process(_ job: Assignment, resume: PipelinePhase) async {
        var failedPhase = resume
        job.record.error = nil
        do {
            let session = try models.makeSession()
            let policy = session.policy
            failedPhase = .preparing
            let page = try await prepare(job)
            if resume == .reviewing {
                failedPhase = .reviewing
                try await review(job, session: session)
            } else {
                let attemptStart = resume == .scoring ? max(1, job.record.attempt) : max(1, (job.record.candidates.map(\.attempt).max() ?? 0) + 1)
                for attempt in attemptStart...max(attemptStart, policy.maximumAttempts) {
                    try Task.checkCancellation()
                    job.record.attempt = attempt
                    if !(resume == .scoring && attempt == attemptStart && job.record.transcript != nil) {
                        failedPhase = .recognizing
                        job.record.phase = .recognizing
                        let start = Date()
                        // The same region, with distinct image treatments; never retry identical deterministic input.
                        let image: Data
                        if attempt == 1 { image = page.enhanced }
                        else if attempt == 2 { image = page.source }
                        else if let strong = page.strong { image = strong }
                        else { image = try await processor.strongImage(page.source) }
                        let preliminary = try await recognizePages(image: image, page: page, job: job, session: session)
                        try Task.checkCancellation()
                        job.record.transcript = preliminary
                        job.record.phaseDurations["ocr_\(attempt)"] = Date().timeIntervalSince(start)
                        try await repository.save(job.record)
                        failedPhase = .verifyingWords
                        let literalStart = Date()
                        let verified = try await verifyLiteral(preliminary, job: job, page: page, session: session)
                        try Task.checkCancellation()
                        job.record.transcript = verified.transcript
                        job.record.candidates.append(OCRCandidate(attempt: attempt, transcript: verified.transcript,
                            rawText: preliminary.text, literalRepairs: verified.repairs, wordVerification: verified.summary,
                            uncertainLineIDs: verified.uncertainLines, uncertainWordRects: verified.uncertainRects,
                            scoredSourceVersion: page.scan.version, readability: verified.readability))
                        job.record.phaseDurations["literal_\(attempt)"] = Date().timeIntervalSince(literalStart)
                        try await repository.save(job.record)
                    }
                    failedPhase = .scoring
                    guard let transcript = job.record.transcript else { throw ModelError.emptyOCR }
                    job.record.phase = .scoring
                    let rendered = try TranscriptRenderer.png(transcript, width: page.width, height: page.height)
                    try await repository.saveRendered(rendered, attempt: attempt, id: job.id)
                    let start = Date()
                    let priorScore = page.readingRegions.count == 1
                        ? job.record.candidates.dropLast().first(where: {
                            $0.transcript.text == transcript.text && $0.scoredSourceVersion == page.scan.version
                        })?.score : nil
                    let score: Double
                    if let priorScore { score = priorScore }
                    else {
                        var scores: [Double] = []
                        let scoringImage = try await processor.recognitionImage(page.source, annotations: page.annotations)
                        for section in ReadingOrder.pageTranscripts(transcript) {
                            let source = try await processor.pageCrop(scoringImage, region: section.region)
                            let render = try TranscriptRenderer.png(section.transcript, width: page.width, height: page.height)
                            scores.append(try await session.score(original: source, rendered: render,
                                text: section.transcript.text))
                        }
                        // Each page must pass; a strong left page must not mask a weak right page.
                        score = scores.min() ?? 0
                    }
                    try Task.checkCancellation()
                    if let index = job.record.candidates.firstIndex(where: { $0.transcript.revision == transcript.revision }) {
                        job.record.candidates[index].score = score
                        job.record.candidates[index].scoredSourceVersion = page.scan.version
                    }
                    job.record.phaseDurations["jev_\(attempt)"] = Date().timeIntervalSince(start)
                    try await repository.save(job.record)
                    let current = job.record.candidates.first { $0.transcript.revision == transcript.revision }
                    if QualityGate.canProceed(score: score, threshold: policy.threshold,
                        verification: current?.wordVerification, readability: current?.readability) {
                        failedPhase = .reviewing
                        try await review(job, session: session)
                        break
                    }
                    if attempt >= policy.maximumAttempts {
                        job.record.transcript = QualityGate.best(job.record.candidates.filter {
                            $0.scoredSourceVersion == page.scan.version
                        })?.transcript ?? transcript
                        // A renderer-dependent whole-page score ranks candidates; it is not an accuracy guarantee.
                        failedPhase = .reviewing
                        try await review(job, session: session)
                    }
                }
            }
        } catch is CancellationError {
            job.record.failedPhase = failedPhase
            job.record.phase = .cancelled
        } catch {
            job.record.failedPhase = failedPhase
            job.record.phase = .failed
            job.record.error = error.localizedDescription
        }
        do { try await repository.save(job.record) }
        catch { globalError = "处理结果尚未保存：\(error.localizedDescription)" }
    }

    private func recognizePages(image: Data, page: PreparedPage, job: Assignment,
                                session: any ModelSession) async throws -> Transcript {
        var texts: [String] = []
        let bodyImage = try await processor.recognitionImage(image, annotations: page.annotations)
        for (index, region) in page.readingRegions.enumerated() {
            try Task.checkCancellation()
            let crop = try await processor.pageCrop(bodyImage, region: region)
            let response = try await session.recognize(image: crop)
            try Task.checkCancellation()
            texts.append(PageScaffolding.bodyText(response.text, annotations: page.annotations))
            try await repository.savePageReading(response, region: region, page: index + 1,
                attempt: job.record.attempt, id: job.id)
            // A completed left page is visible while the right page is still being read.
            job.record.transcript = ReadingOrder.transcript(texts: texts, hints: page.hints, regions: page.readingRegions)
            try await repository.save(job.record)
            if response.truncated { throw ModelError.truncated }
        }
        guard let transcript = job.record.transcript else { throw ModelError.emptyOCR }
        return transcript
    }

    private struct VerifiedTranscript {
        let transcript: Transcript
        let repairs: [LiteralRepair]
        let summary: WordVerificationSummary
        let uncertainLines: [Int]
        let uncertainRects: [PageRect]
        let readability: ReadabilityEvidence
    }

    private func verifyLiteral(_ transcript: Transcript, job: Assignment, page: PreparedPage,
                               session: any ModelSession) async throws -> VerifiedTranscript {
        let inventory = WordAlignment.inventory(transcript, hints: page.words)
        let regionHints = inventory.regions.map(\.cropHint)
        var checks: [WordCheck] = []
        var crops: [Data] = []
        let cachePrefix = "\(session.recognitionIdentity):\(PhotoProcessor.version):word-pass-v2-source:\(job.id)"
        job.record.phase = .verifyingWords
        job.record.wordChecksCompleted = 0; job.record.wordChecksTotal = inventory.regions.count
        try await repository.save(job.record)
        let wordStart = Date()

        // Round two reads EVERY physical word region, including words that the
        // page OCR and Vision agree on. Jev is not called until this round ends.
        for region in inventory.regions {
            try Task.checkCancellation()
            let crop = try await processor.wordCrop(page.enhanced, hint: region.cropHint, neighbors: regionHints)
            crops.append(crop)
            let key = "\(cachePrefix):\(region.rect)"
            let reading: CachedReading
            if let cached = wordReadings[key] { reading = cached }
            else {
                do {
                    let response = try await session.recognize(image: crop)
                    reading = CachedReading(text: response.truncated ? nil : WordAlignment.lexicalReading(response.text))
                } catch ModelError.emptyOCR {
                    reading = CachedReading(text: nil)
                }
                try Task.checkCancellation()
                wordReadings[key] = reading
            }
            let checkSource = reading.text == nil || reading.text != region.original
                || reading.text != WordAlignment.lexicalReading(region.hint)
            var sourceReading: String?
            if checkSource {
                let sourceKey = key + ":source"
                if let cached = wordReadings[sourceKey] { sourceReading = cached.text }
                else {
                    let sourceCrop = try await processor.wordCrop(page.source, hint: region.cropHint, neighbors: regionHints)
                    do {
                        let response = try await session.recognize(image: sourceCrop)
                        sourceReading = response.truncated ? nil : WordAlignment.lexicalReading(response.text)
                    } catch ModelError.emptyOCR { sourceReading = nil }
                    try Task.checkCancellation()
                    wordReadings[sourceKey] = CachedReading(text: sourceReading)
                }
            }
            checks.append(WordCheck(region: region, isolated: reading.text, sourceReading: sourceReading, sourceChecked: checkSource))
            job.record.wordChecksCompleted = checks.count
            // A checkpoint allows inspection and recovery without concealing a
            // skipped or unreadable word behind a completed progress indicator.
            try await repository.saveWordChecks(checks, attempt: job.record.attempt, id: job.id)
            try await repository.save(job.record)
        }
        job.record.phaseDurations["word_ocr_\(job.record.attempt)"] = Date().timeIntervalSince(wordStart)
        job.record.phase = .scoring
        try await repository.save(job.record)
        var accepted: [(NSRange, LiteralRepair)] = []
        for index in checks.indices {
            try Task.checkCancellation()
            let region = checks[index].region
            guard let original = region.original, let range = region.range else {
                checks[index].unresolved = true; continue
            }
            let alternatives = [original, checks[index].isolated, checks[index].sourceReading,
                WordAlignment.lexicalReading(region.hint)].compactMap { $0 }
            var candidates: [String] = []
            for text in alternatives where !candidates.contains(text) { candidates.append(text) }
            checks[index].selected = original
            checks[index].evidence = "whole_page"
            if candidates.count > 1 {
                let normalized: (Data, [String: Data])
                do { normalized = try TranscriptRenderer.normalizedWordImages(original: crops[index], candidates: candidates) }
                catch PhotoError.emptyWordRegion {
                    checks[index].unresolved = true; checks[index].evidence = "empty_word_region"; continue
                }
                for text in candidates {
                    let key = "\(cachePrefix):\(session.verificationIdentity):\(TranscriptRenderer.wordVersion):\(region.rect):\(candidates.joined(separator: "|")):\(text)"
                    let score: Double
                    if let cached = wordScores[key] { score = cached }
                    else {
                        guard let rendered = normalized.1[text] else { throw PhotoError.renderFailed }
                        score = try await session.score(original: normalized.0, rendered: rendered, text: text)
                        wordScores[key] = score
                    }
                    checks[index].scores[text] = score
                }
                let independent = LiteralVerification.independentPreference(original: original,
                    isolated: checks[index].isolated, hint: region.hint,
                    originalScore: checks[index].scores[original], literalScore: checks[index].isolated.flatMap { checks[index].scores[$0] })
                if let independent, let literal = checks[index].isolated,
                   let originalScore = checks[index].scores[original], let literalScore = checks[index].scores[literal] {
                    let repair = LiteralRepair(original: original, literal: literal, rect: region.rect,
                                               originalScore: originalScore, literalScore: literalScore)
                    accepted.append((range, repair)); checks[index].selected = literal; checks[index].evidence = independent
                } else if let originalScore = checks[index].scores[original],
                   let best = checks[index].scores.max(by: { $0.value < $1.value }), best.key != original,
                   LiteralVerification.prefersAlternative(originalScore: originalScore, alternativeScore: best.value) {
                    let repair = LiteralRepair(original: original, literal: best.key, rect: region.rect,
                                               originalScore: originalScore, literalScore: best.value)
                    accepted.append((range, repair)); checks[index].selected = best.key; checks[index].evidence = "visual_preference"
                }
            }
            // A Jev win does not erase disagreement between actual image readings.
            checks[index].unresolved = checks[index].readingsDisagree
        }
        let result = ReadingOrder.replacing(accepted.map { ($0.0, $0.1.literal) }, in: transcript)
        try await repository.saveWordChecks(checks, attempt: job.record.attempt, id: job.id)
        let unresolved = checks.filter(\.unresolved)
        let summary = WordVerificationSummary(totalRegions: inventory.regions.count, checkedRegions: checks.count,
            transcriptWords: inventory.transcriptWords, locatedWords: inventory.locatedWords, unresolvedRegions: unresolved.count)
        try await repository.saveTextStructure(result, checks: checks, page: page, attempt: job.record.attempt, id: job.id)
        return VerifiedTranscript(transcript: result,
            repairs: accepted.map(\.1), summary: summary,
            uncertainLines: Array(Set(unresolved.map { $0.region.lineID })).sorted(), uncertainRects: unresolved.map { $0.region.rect },
            readability: ReadabilityEvidence(checks: checks, totalRegions: inventory.regions.count))
    }

    private func review(_ job: Assignment, session: any ModelSession) async throws {
        guard let transcript = job.record.transcript else { throw ModelError.emptyOCR }
        job.record.phase = .reviewing
        // Keep the last valid batch if this new model request fails.
        try await repository.save(job.record)
        let start = Date()
        let candidate = job.record.candidates.first { $0.transcript.revision == transcript.revision }
        let checks = candidate?.scoredSourceVersion == job.page?.scan.version
            ? try await repository.wordChecks(attempt: candidate?.attempt ?? job.record.attempt, id: job.id) : []
        let result = try await session.review(transcript: transcript)
        try Task.checkCancellation()
        guard job.record.transcript?.revision == transcript.revision else { return }
        let uncertainRects = candidate?.uncertainWordRects ?? []
        let inventory = WordAlignment.inventory(transcript, hints: job.page?.words ?? [])
        var visible: [ReviewIssue] = [], deferred: [ReviewIssue] = []
        for issue in result.issues {
            if ReviewLiteralSupport.canAnnotate(issue, transcript: transcript, inventory: inventory, uncertainRects: uncertainRects, checks: checks, humanConfirmed: job.record.humanConfirmed) {
                visible.append(issue)
            } else { deferred.append(issue) }
        }
        job.record.issues = visible
        if job.record.teacherReview != nil { job.record.teacherReview?.completedAt = nil }
        job.record.deferredReviewIssues = deferred
        job.record.rejectedIssues = result.rejectedCount
        job.record.reviewRejections = result.rejections
        try await repository.saveReview(result, transcript: transcript, deferred: job.record.deferredReviewIssues ?? [], id: job.id)
        job.record.phaseDurations["review"] = Date().timeIntervalSince(start)
        for stage in ["spelling_clues", "draft", "grammar", "context", "validation", "usage", "localization"] {
            job.record.phaseDurations["review_\(stage)"] = result.modelEvidence?.stageSeconds[stage]
        }
        job.record.phase = .complete; job.record.failedPhase = nil
        if selectedID == job.id { selectedIssueID = job.record.pendingIssues.first?.id }
    }

    func reanchorReview(_ job: Assignment) {
        guard task == nil, !deleting.contains(job.id), assignments.contains(where: { $0.id == job.id }),
              !job.record.phase.isRunning, let transcript = job.record.transcript,
              let rejections = job.record.reviewRejections else { return }
        let result = IssueAnchoring.anchor(rejections.map(\.proposal), to: transcript, recoverUniqueOccurrence: true, recoverUniqueLine: true)
        let inventory = WordAlignment.inventory(transcript, hints: job.page?.words ?? [])
        let uncertain = inventory.unlocatedRanges + inventory.regions
            .filter { job.uncertainWordRects.contains($0.rect) }.compactMap(\.range)
        let deferred = result.issues.filter { issue in uncertain.contains { NSIntersectionRange($0, issue.range).length > 0 } }
        let recovered = result.issues.filter { issue in !uncertain.contains { NSIntersectionRange($0, issue.range).length > 0 } }
        for issue in recovered where !job.record.issues.contains(where: { $0.range == issue.range && $0.kind == issue.kind }) {
            job.record.issues.append(issue)
        }
        job.record.deferredReviewIssues = (job.record.deferredReviewIssues ?? []) + deferred
        job.record.reviewRejections = result.rejections; job.record.rejectedIssues = result.rejectedCount
        job.record.issues.sort { $0.start < $1.start }
        activeID = job.id
        task = Task {
            do {
                try await repository.saveReview(result, transcript: transcript, deferred: deferred, id: job.id, source: "reanchor")
                try await repository.save(job.record)
            } catch { globalError = "建议定位结果尚未保存：\(error.localizedDescription)" }
            activeID = nil; task = nil; pump()
        }
    }

    func retry(_ job: Assignment, entireOCR: Bool = false) {
        guard !job.savingReview, job.reviewSaveError == nil, activeID != job.id, !job.record.phase.isRunning, !restarting.contains(job.id),
              !deleting.contains(job.id), assignments.contains(where: { $0.id == job.id }) else { return }
        if entireOCR {
            job.record.teacherReview?.completedAt = nil
            restarting.insert(job.id)
            let old = job.record
            Task {
                do {
                    try await repository.archiveBeforeStructureChange(old)
                    restarting.remove(job.id)
                    enqueueRetry(job, entireOCR: true)
                } catch {
                    restarting.remove(job.id)
                    globalError = "无法保存上一版识别记录，尚未重新识别：\(error.localizedDescription)"
                }
            }
        } else { enqueueRetry(job, entireOCR: false) }
    }
    private func enqueueRetry(_ job: Assignment, entireOCR: Bool) {
        guard activeID != job.id, !job.record.phase.isRunning, !deleting.contains(job.id),
              assignments.contains(where: { $0.id == job.id }) else { return }
        if entireOCR {
            job.page = nil
            job.record.candidates = []; job.record.attempt = 0; job.record.transcript = nil
            job.record.phaseDurations = [:]
            job.record.issues = []; job.record.humanConfirmed = false
            job.record.rejectedIssues = 0; job.record.reviewRejections = nil; job.record.deferredReviewIssues = nil
            job.record.wordChecksCompleted = nil; job.record.wordChecksTotal = nil
            pending[job.id] = .recognizing
        } else {
            let phase = job.record.failedPhase ?? (job.record.transcript != nil ? .reviewing : .recognizing)
            pending[job.id] = phase == .scoring || phase == .reviewing ? phase : .recognizing
        }
        job.record.phase = .queued; job.record.error = nil
        pump()
    }

    func cancel() { task?.cancel() }

    func confirmTranscript(_ job: Assignment, text: String) {
        guard activeID != job.id, !job.savingReview, job.reviewSaveError == nil, !deleting.contains(job.id),
              assignments.contains(where: { $0.id == job.id }), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let previous = job.record
        job.savingReview = true
        Task {
            do {
                try await repository.archiveBeforeStructureChange(previous)
                job.record.transcript = LineAlignment.makeTranscript(text: text, hints: job.page?.hints ?? [])
                job.record.teacherReview?.completedAt = nil
                job.record.humanConfirmed = true; job.record.issues = []
                job.record.rejectedIssues = 0; job.record.reviewRejections = nil; job.record.deferredReviewIssues = nil
                job.record.phase = .queued; job.record.error = nil
                selectedIssueID = nil; pending[job.id] = .reviewing
                job.savingReview = false
                pump()
            } catch {
                job.savingReview = false
                globalError = "无法保存校对前的版本，原识别稿未改动：\(error.localizedDescription)"
            }
        }
    }

    /// Preserve the older entry point while recording teacher judgments separately.
    func toggleDismiss(_ job: Assignment, issueID: UUID) {
        guard let issue = job.record.issues.first(where: { $0.id == issueID }) else { return }
        if let decision = job.record.review.decision(for: issue) {
            restoreSuggestion(decision, job: job, undoManager: nil)
        } else { resolve(job, issue: issue, as: .keepOriginal) }
    }

    func checkModels() async { await models.checkReadiness() }

    func showOriginal(_ job: Assignment) {
        Task { let url = await repository.originalURL(job.record); NSWorkspace.shared.open(url) }
    }

    func export(_ job: Assignment, annotated: Bool) {
        guard let transcript = job.record.transcript else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(job.record.title)-识别结果\(annotated ? "（含批注）" : "").md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let content = annotated ? MarkdownExport.annotated(transcript, issues: job.record.issues,
                    humanConfirmed: job.record.humanConfirmed, teacherReview: job.record.review) : MarkdownExport.original(transcript)
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch { self.globalError = "导出失败：\(error.localizedDescription)" }
        }
    }
}

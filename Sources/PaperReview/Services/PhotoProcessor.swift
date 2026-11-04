import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision
import PaperReviewCore

nonisolated struct ScanMetadata: Codable, Sendable {
    struct Point: Codable, Sendable { let x: Double; let y: Double }
    struct PageCorrection: Codable, Sendable {
        let region: PageRect; let method: String; let cropped: Bool; let corners: [Point]
    }
    let version: String
    let perspectiveCorrected: Bool
    let originalWidth: Int
    let originalHeight: Int
    let corners: [Point]
    let pages: [PageCorrection]?
}

nonisolated struct PreparedPage: Sendable {
    let source: Data
    let enhanced: Data
    let strong: Data?
    let width: Int
    let height: Int
    let hints: [TextHint]
    let words: [WordHint]
    let readingRegions: [PageRect]
    let annotations: [PageAnnotation]
    let cropped: Bool
    let scan: ScanMetadata
}

enum PhotoError: LocalizedError, Equatable {
    case unreadable, renderFailed, emptyWordRegion
    case visionStage(String, String)
    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取这张照片。请使用 JPEG、PNG、HEIC 或 TIFF 图片。"
        case .renderFailed: "照片处理失败。原片仍保留，可重新导入。"
        case .emptyWordRegion: "该词区没有足够清晰的笔迹，已保留整页识别结果。"
        case .visionStage(let stage, let detail): "系统\(stage)未完成，请重试照片处理。\(detail)"
        }
    }
}

actor PhotoProcessor {
    nonisolated static let version = "document-scan-v4-page-perspective"
    private let context = CIContext(options: [.cacheIntermediates: false])
    func prepare(_ data: Data) throws -> PreparedPage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { throw PhotoError.unreadable }
        try Task.checkCancellation()
        let image = CIImage(cgImage: cg)
        let originalObservations = try recognize(cg)
        let initialHints = originalObservations.compactMap { observation -> TextHint? in
            guard let text = observation.topCandidates(1).first else { return nil }
            return TextHint(text: text.string, rect: Self.pageRect(observation.boundingBox))
        }
        let initialRegions = ReadingOrder.regions(hints: initialHints, aspectRatio: Double(cg.width) / Double(cg.height))
        var corrected: [PageRectifier.Result] = []
        for region in initialRegions {
            let crop = CGRect(x: region.x * Double(cg.width), y: 0, width: region.width * Double(cg.width), height: Double(cg.height))
                .integral.intersection(image.extent)
            let local = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            guard let localCG = context.createCGImage(local, from: local.extent) else { throw PhotoError.renderFailed }
            let text = initialRegions.count == 1 ? originalObservations : try recognize(localCG)
            let result = try PageRectifier.rectify(localCG, text: text)
            corrected.append(PageRectifier.flattenRulings(result, context: context))
        }
        var page = corrected[0].image
        if corrected.count > 1 {
            let height = corrected.map { $0.image.extent.height }.max() ?? 1
            var x: CGFloat = 0
            var stitched = CIImage(color: .white)
            for result in corrected {
                let scale = height / result.image.extent.height
                let part = result.image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(translationX: x, y: 0))
                stitched = part.composited(over: stitched); x += part.extent.width
            }
            page = stitched.cropped(to: CGRect(x: 0, y: 0, width: x, height: height).integral)
        }
        guard let pageCG = context.createCGImage(page, from: page.extent.integral) else { throw PhotoError.renderFailed }
        let observations = try recognize(pageCG)
        let full = CGRect(x: 0, y: 0, width: pageCG.width, height: pageCG.height)
        page = CIImage(cgImage: pageCG)
        // Apple's document filter removes illumination gradients without replacing
        // ink with a hard black/white threshold (which can erase pencil strokes).
        let enhancedPage = try enhancedImage(page, amount: 2, inkPower: 1.35, midpoint: 0.42).cropped(to: full)
        let strongPage = try enhancedImage(page, amount: 4, inkPower: 1.6, midpoint: 0.36).cropped(to: full)
        let readable = observations.filter { $0.topCandidates(1).first != nil }
        let fragments = readable.map { observation -> TextHint in
            let candidate = observation.topCandidates(1)[0]
            return TextHint(text: candidate.string, rect: Self.pageRect(observation.boundingBox), confidence: Double(candidate.confidence))
        }
        let rectangles = VNDetectRectanglesRequest()
        rectangles.maximumObservations = 100; rectangles.minimumAspectRatio = 0.3; rectangles.maximumAspectRatio = 2
        rectangles.minimumSize = 0.01; rectangles.minimumConfidence = 0.5; rectangles.quadratureTolerance = 25
        do { try VNImageRequestHandler(cgImage: pageCG).perform([rectangles]) }
        catch { throw PhotoError.visionStage("边栏定位", error.localizedDescription) }
        let aspect = Double(pageCG.width) / Double(pageCG.height)
        let annotations = PageScaffolding.annotations(fragments: fragments,
            rectangles: (rectangles.results ?? []).map { Self.pageRect($0.boundingBox) }, aspectRatio: aspect)
        let bodyIndices = fragments.indices.filter { index in !annotations.contains { PageScaffolding.covers(fragments[index].rect, with: $0) } }
        let bodyFragments = bodyIndices.map { fragments[$0] }
        let readingRegions = ReadingOrder.regions(hints: bodyFragments, aspectRatio: aspect)
        let groups = ReadingOrder.rowGroups(hints: bodyFragments, regions: readingRegions).map { $0.map { bodyIndices[$0] } }
        let hints = groups.map { TextRowGrouping.merged($0, hints: fragments) }
        var words: [WordHint] = []
        let regex = try NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)*|[0-9]+")
        for (rowIndex, group) in groups.enumerated() {
          for index in group {
            let observation = readable[index]
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text), let word = try? candidate.boundingBox(for: range) else { continue }
                words.append(WordHint(lineID: rowIndex + 1, text: String(text[range]), rect: Self.pageRect(word.boundingBox), confidence: Double(candidate.confidence)))
            }
          }
        }
        let corrections = zip(initialRegions, corrected).map { region, result in
            ScanMetadata.PageCorrection(region: region, method: result.method, cropped: result.cropped,
                corners: (result.quad?.points ?? []).map { .init(x: $0.x, y: $0.y) })
        }
        let metadata = ScanMetadata(version: Self.version, perspectiveCorrected: corrected.contains { $0.method != "unchanged" },
            originalWidth: cg.width, originalHeight: cg.height,
            corners: initialRegions.count == 1 ? corrections[0].corners : [], pages: corrections)
        return PreparedPage(source: try png(page), enhanced: try png(enhancedPage), strong: try png(strongPage),
            width: pageCG.width, height: pageCG.height, hints: hints, words: words,
            readingRegions: readingRegions, annotations: annotations, cropped: corrected.contains { $0.cropped }, scan: metadata)
    }

    private func enhancedImage(_ image: CIImage, amount: Float, inkPower: Float, midpoint: Float) throws -> CIImage {
        let filter = CIFilter.documentEnhancer()
        filter.inputImage = image; filter.amount = amount
        guard let output = filter.outputImage else { throw PhotoError.renderFailed }
        let curve = CIFilter.toneCurve()
        curve.inputImage = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": inkPower])
        curve.point0 = CGPoint(x: 0, y: 0); curve.point1 = CGPoint(x: 0.25, y: 0.18)
        curve.point2 = CGPoint(x: 0.5, y: CGFloat(midpoint)); curve.point3 = CGPoint(x: 0.75, y: 0.72)
        curve.point4 = CGPoint(x: 1, y: 1)
        guard let ink = curve.outputImage else { throw PhotoError.renderFailed }
        return ink.cropped(to: image.extent)
    }
    func strongImage(_ data: Data) throws -> Data {
        guard let image = CIImage(data: data) else { throw PhotoError.unreadable }
        return try png(enhancedImage(image, amount: 4, inkPower: 1.6, midpoint: 0.36))
    }

    private func recognize(_ image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.005
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { throw PhotoError.visionStage("文字定位", error.localizedDescription) }
        return request.results ?? []
    }
    private static func pageRect(_ box: CGRect) -> PageRect {
        PageRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }
    func wordCrop(_ data: Data, hint: WordHint, neighbors: [WordHint]) throws -> Data {
        guard let image = CIImage(data: data) else { throw PhotoError.unreadable }
        let extent = image.extent
        let rect = hint.rect
        let sameLine = neighbors.filter { $0.lineID == hint.lineID }
        let before = sameLine.filter { $0.rect.x < rect.x }.map { $0.rect.x + $0.rect.width }.max() ?? 0
        let after = sameLine.filter { $0.rect.x > rect.x }.map { $0.rect.x }.min() ?? 1
        // Stop padding at inter-word whitespace; neighboring ink would change the ROI's content.
        let leftPad = min(8, max(0, (rect.x - before) * extent.width / 2))
        let rightPad = min(8, max(0, (after - rect.x - rect.width) * extent.width / 2))
        let pixel = CGRect(x: rect.x * extent.width - leftPad, y: (1 - rect.y - rect.height) * extent.height - 12,
            width: rect.width * extent.width + leftPad + rightPad, height: rect.height * extent.height + 24)
            .integral.intersection(extent)
        return try png(image.cropped(to: pixel))
    }
    func pageCrop(_ data: Data, region: PageRect) throws -> Data {
        guard region != ReadingOrder.fullPage else { return data }
        guard let image = CIImage(data: data) else { throw PhotoError.unreadable }
        let extent = image.extent
        let rect = CGRect(x: region.x * extent.width, y: (1 - region.y - region.height) * extent.height,
            width: region.width * extent.width, height: region.height * extent.height).integral.intersection(extent)
        guard rect.width > 0 && rect.height > 0 else { throw PhotoError.renderFailed }
        return try png(image.cropped(to: rect))
    }
    /// Mask only proven form furniture in the model input; the displayed scan and
    /// original file stay intact. Jev receives the same content mask as OCR.
    func recognitionImage(_ data: Data, annotations: [PageAnnotation]) throws -> Data {
        guard !annotations.isEmpty else { return data }
        guard var image = CIImage(data: data) else { throw PhotoError.unreadable }
        let extent = image.extent
        for annotation in annotations {
            let box = annotation.rect
            let rect = CGRect(x: box.x * extent.width, y: (1 - box.y - box.height) * extent.height,
                width: box.width * extent.width, height: box.height * extent.height).insetBy(dx: -2, dy: -2).intersection(extent)
            image = CIImage(color: .white).cropped(to: rect).composited(over: image)
        }
        return try png(image.cropped(to: extent))
    }
    private func png(_ image: CIImage) throws -> Data {
        guard let cg = context.createCGImage(image, from: image.extent) else { throw PhotoError.renderFailed }
        let data = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw PhotoError.renderFailed }
        CGImageDestinationAddImage(target, cg, nil)
        guard CGImageDestinationFinalize(target) else { throw PhotoError.renderFailed }
        return data as Data
    }
}

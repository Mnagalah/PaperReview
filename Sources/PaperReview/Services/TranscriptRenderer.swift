import AppKit
import PaperReviewCore

/// A fixed, versioned Jev renderer, deliberately separate from error annotations.
enum TranscriptRenderer {
    static let version = "native-plain-flow-v3"
    static let wordVersion = "word-ink-height-v1"
    /// Jev compares the same crop and natural-font candidates on equal canvases.
    /// Only uniform scaling and white padding are used; UI layout is independent.
    static func normalizedWordImages(original: Data, candidates: [String]) throws -> (Data, [String: Data]) {
        let width = wordCanvasWidth(candidates)
        let inputs = try [original] + candidates.map { try wordPNG($0, canvasWidth: width) }
        let ink = try inputs.map { data -> CGImage in
            guard let bitmap = NSBitmapImageRep(data: data), let image = bitmap.cgImage else { throw PhotoError.renderFailed }
            var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
                    let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                    if luminance < 0.65 { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y) }
                }
            }
            guard maxX >= minX, maxY >= minY else { throw PhotoError.emptyWordRegion }
            guard let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { throw PhotoError.renderFailed }
            return cropped
        }
        let inkHeight: CGFloat = 64
        let widths = ink.map { CGFloat($0.width) / CGFloat($0.height) * inkHeight }
        let canvasWidth = Int(ceil((widths.max() ?? 0) + 48))
        let outputs = try zip(ink, widths).map { cg, width -> Data in
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvasWidth, pixelsHigh: 112,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw PhotoError.renderFailed }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: canvasWidth, height: 112).fill()
            NSImage(cgImage: cg, size: .zero).draw(in: NSRect(x: (CGFloat(canvasWidth) - width) / 2, y: 24, width: width, height: inkHeight))
            NSGraphicsContext.restoreGraphicsState()
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw PhotoError.renderFailed }
            return data
        }
        return (outputs[0], Dictionary(uniqueKeysWithValues: zip(candidates, outputs.dropFirst())))
    }
    static func wordCanvasWidth(_ words: [String]) -> Int {
        let font = NSFont(name: "Helvetica", size: 46) ?? .systemFont(ofSize: 46)
        return max(320, words.map { Int(($0 as NSString).size(withAttributes: [.font: font]).width) + 32 }.max() ?? 320)
    }
    static func wordPNG(_ text: String, canvasWidth: Int) throws -> Data {
        let font = NSFont(name: "Helvetica", size: 46) ?? .systemFont(ofSize: 46)
        let width = canvasWidth
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw PhotoError.renderFailed }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: 100).fill()
        (text as NSString).draw(at: NSPoint(x: 16, y: 28), withAttributes: [.font: font, .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw PhotoError.renderFailed }
        return data
    }
    static func png(_ transcript: Transcript, width: Int, height: Int) throws -> Data {
        // Scoring has its own fixed typography, independent of UI zoom and annotations.
        let targetWidth = 1000
        let padding: CGFloat = 40
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 7
        let font = NSFont(name: "Helvetica", size: 26) ?? .systemFont(ofSize: 26)
        let text = NSAttributedString(string: transcript.text, attributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style])
        let measure = text.boundingRect(with: NSSize(width: CGFloat(targetWidth) - padding * 2, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let targetHeight = max(200, Int(ceil(measure.height + padding * 2)))
        guard targetHeight <= 16000,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: targetWidth, pixelsHigh: targetHeight,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw PhotoError.renderFailed }
        NSGraphicsContext.saveGraphicsState()
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(targetHeight)); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight).fill()
        text.draw(with: NSRect(x: padding, y: padding, width: CGFloat(targetWidth) - padding * 2,
                              height: CGFloat(targetHeight) - padding * 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw PhotoError.renderFailed }
        return data
    }

}

enum TextDrawing {
    static func font(zoom: CGFloat) -> NSFont { .systemFont(ofSize: 18 * zoom) }
    static func height(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; style.lineSpacing = font.pointSize * 0.18
        let size = (text as NSString).boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: style])
        return ceil(max(size.height, font.ascender - font.descender + font.leading))
    }
    private static func attributed(_ text: String, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; style.lineSpacing = font.pointSize * 0.18
        return NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
    static func characterIndex(_ point: NSPoint, text: String, rect: NSRect, font: NSFont) -> Int? {
        guard rect.contains(point), !text.isEmpty else { return nil }
        let storage = NSTextStorage(attributedString: attributed(text, font: font, color: .textColor))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: rect.size); container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let glyph = manager.glyphIndex(for: NSPoint(x: point.x - rect.minX, y: point.y - rect.minY), in: container)
        guard glyph < manager.numberOfGlyphs else { return nil }
        return manager.characterIndexForGlyph(at: glyph)
    }
    static func rangeRect(_ range: NSRange, text: String, rect: NSRect, font: NSFont) -> NSRect? {
        guard range.location >= 0, NSMaxRange(range) <= text.utf16.count else { return nil }
        let storage = NSTextStorage(attributedString: attributed(text, font: font, color: .textColor))
        let manager = NSLayoutManager(), container = NSTextContainer(size: rect.size)
        container.lineFragmentPadding = 0; storage.addLayoutManager(manager); manager.addTextContainer(container)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: rect.minX, dy: rect.minY)
    }
    static func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor,
                     highlights: [(NSRange, NSColor)] = [], uncertainties: [NSRange] = [], underlines: [(NSRange, NSColor)] = []) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let attributed = attributed(text, font: font, color: color)
        for range in uncertainties where range.location >= 0 && NSMaxRange(range) <= attributed.length {
            attributed.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                                      .underlineColor: NSColor.systemPurple,
                                      .backgroundColor: NSColor.systemPurple.withAlphaComponent(0.14)], range: range)
        }
        for (range, color) in highlights where NSMaxRange(range) <= attributed.length && range.location >= 0 {
            attributed.addAttributes([.backgroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
        }
        for (range, color) in underlines where range.location >= 0 && NSMaxRange(range) <= attributed.length {
            attributed.addAttributes(WorkspaceStyle.annotationAttributes(color: color,
                light: NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) != .darkAqua,
                highContrast: WorkspaceStyle.isHighContrast(NSAppearance.currentDrawing())), range: range)
        }
        // Never fit a glyph to the photographed bounding box. Natural font metrics
        // and wrapping are preserved; the paired zoom scales the entire page equally.
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

import SwiftUI
import AppKit
import QuartzCore
import PaperReviewCore

enum ComparisonMode: String, CaseIterable, Identifiable {
    case sideBySide, stacked, wipe
    var id: String { rawValue }
    var title: String {
        switch self { case .sideBySide: "左右对照"; case .stacked: "上下对照"; case .wipe: "滑动对照" }
    }
    var symbol: String {
        switch self { case .sideBySide: "rectangle.split.2x1"; case .stacked: "rectangle.split.1x2"; case .wipe: "rectangle.lefthalf.filled" }
    }
}

/// Two persistent viewports share document coordinates. Zoom never pushes the other page off-screen.
struct PairedDocumentView: NSViewRepresentable {
    let image: NSImage?
    let transcript: Transcript?
    let issues: [ReviewIssue]
    let uncertainLineIDs: [Int]
    let wordRegions: [WordRegion]
    let uncertainWordRects: [PageRect]
    let unlocatedTextRanges: [NSRange]
    let selectedIssueID: UUID?
    let aspect: Double
    let zoom: Double
    let mode: ComparisonMode
    let wipeFraction: Double
    let onZoomChange: (Double) -> Void
    let onWipeChange: (Double) -> Void
    let onLineClick: (Int) -> Void
    let onIssueClick: (UUID) -> Void
    var sourceOnly = false
    var position: CGPoint = .zero
    var onPositionChange: (CGPoint) -> Void = { _ in }
    func makeNSView(context: Context) -> PairedScrollView { PairedScrollView() }
    func updateNSView(_ view: PairedScrollView, context: Context) {
        view.source.image = image
        view.source.transcript = transcript
        view.source.uncertainLineIDs = uncertainLineIDs
        view.source.selectedIssue = issues.first { $0.id == selectedIssueID }
        view.source.issues = issues; view.source.wordRegions = wordRegions
        view.source.uncertainWordRects = uncertainWordRects; view.source.onIssueClick = onIssueClick
        view.text.transcript = transcript; view.text.issues = issues
        view.text.uncertainLineIDs = uncertainLineIDs; view.text.selectedIssueID = selectedIssueID
        view.text.onLineClick = onLineClick
        view.text.onIssueClick = onIssueClick; view.text.wordRegions = wordRegions; view.text.uncertainWordRects = uncertainWordRects
        view.text.unlocatedTextRanges = unlocatedTextRanges
        view.text.setAccessibilityElement(true)
        view.text.setAccessibilityRole(.textArea)
        view.text.setAccessibilityLabel("识别原文。" + (transcript?.text ?? ""))
        view.aspect = aspect; view.zoom = zoom; view.mode = mode; view.wipeFraction = wipeFraction
        view.onZoomChange = onZoomChange; view.onWipeChange = onWipeChange
        view.sourceOnly = sourceOnly
        view.onPositionChange = onPositionChange
        view.restorePosition(position)
        view.focusIssueID = selectedIssueID
        view.needsLayout = true; view.source.needsDisplay = true; view.text.needsDisplay = true
    }
}

final class PairedScrollView: NSView {
    let source = SourcePageView()
    let text = TranscriptPageView()
    private let left = NSScrollView()
    private let right = NSScrollView()
    private let overlay = NSScrollView()
    private let wipeCanvas = WipeCanvasView()
    private let divider = WipeDividerView()
    var aspect = 1.0
    var zoom = 1.0
    var mode: ComparisonMode = .sideBySide
    var wipeFraction = 0.5
    var onZoomChange: ((Double) -> Void)?
    var onWipeChange: ((Double) -> Void)?
    var sourceOnly = false
    var onPositionChange: ((CGPoint) -> Void)?
    var focusIssueID: UUID?
    private var lastFocusedID: UUID?
    private var pendingPosition: CGPoint?
    private var installedMode: ComparisonMode?
    private var pinchStart = 1.0
    private var syncing = false
    override var isFlipped: Bool { true }
    private var primary: NSScrollView { mode == .wipe ? overlay : left }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for scroll in [left, right, overlay] {
            scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true; scroll.borderType = .noBorder
            scroll.contentView.postsBoundsChangedNotifications = true
            scroll.drawsBackground = false
            addSubview(scroll)
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }
        left.setAccessibilityLabel("原照片"); right.setAccessibilityLabel("识别原文")
        overlay.setAccessibilityLabel("滑动对照：左侧照片，右侧转写")
        addSubview(divider)
        divider.onChange = { [weak self] fraction in
            guard let self else { return }
            self.wipeFraction = fraction; self.updateWipe(); self.onWipeChange?(fraction)
        }
        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(magnified(_:)))
        addGestureRecognizer(pinch)
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func layout() {
        super.layout()
        syncing = true
        let margin = WorkspaceGrid.paneInset, gap = WorkspaceGrid.documentGap
        let changed = installedMode != mode
        let oldPrimary = installedMode == .wipe ? overlay : left
        let oldPoint = oldPrimary.contentView.bounds.origin
        let oldSize = source.frame.size
        if changed {
            left.documentView = nil; right.documentView = nil; overlay.documentView = nil
            source.layer?.mask = nil; text.layer?.mask = nil
            if mode == .wipe {
                source.wantsLayer = true; text.wantsLayer = true
                wipeCanvas.source = source; wipeCanvas.text = text
                wipeCanvas.addSubview(source); wipeCanvas.addSubview(text); overlay.documentView = wipeCanvas
            } else { left.documentView = source; right.documentView = text }
            installedMode = mode
        }
        left.isHidden = mode == .wipe; right.isHidden = mode == .wipe || sourceOnly
        overlay.isHidden = mode != .wipe; divider.isHidden = mode != .wipe
        text.paperBackground = mode == .wipe
        let fullWidth = max(1, bounds.width - margin * 2)
        let fullHeight = max(1, bounds.height - margin * 2)
        let pane = mode == .sideBySide && !sourceOnly ? max(1, (fullWidth - gap) / 2) : fullWidth
        let paneHeight = mode == .stacked && !sourceOnly ? max(1, (fullHeight - gap) / 2) : fullHeight
        left.frame = NSRect(x: margin, y: margin, width: pane, height: paneHeight)
        right.frame = NSRect(x: mode == .sideBySide ? margin + pane + gap : margin,
            y: mode == .stacked ? margin + paneHeight + gap : margin, width: pane, height: paneHeight)
        overlay.frame = NSRect(x: margin, y: margin, width: fullWidth, height: fullHeight)
        text.zoom = zoom
        // Keep source rows intact at a natural font size. Narrow viewports scroll
        // together horizontally instead of introducing new transcription wraps.
        let documentWidth = max(pane * zoom, text.requiredWidth())
        let pageHeight = max(1, documentWidth * aspect)
        text.pageHeight = pageHeight; source.pageHeight = pageHeight
        let height = max(pageHeight, text.requiredHeight(width: documentWidth, pageHeight: pageHeight))
        let size = NSSize(width: documentWidth, height: height)
        source.frame = NSRect(origin: .zero, size: size); text.frame = NSRect(origin: .zero, size: size)
        wipeCanvas.frame = NSRect(origin: .zero, size: size)
        let point = pendingPosition ?? (changed && oldSize.width > 0 && oldSize.height > 0
            ? NSPoint(x: oldPoint.x / oldSize.width * size.width, y: oldPoint.y / oldSize.height * size.height)
            : primary.contentView.bounds.origin)
        pendingPosition = nil
        for scroll in mode == .wipe ? [overlay] : [left, right] {
            scroll.contentView.scroll(to: point); scroll.reflectScrolledClipView(scroll.contentView)
        }
        updateWipe()
        syncing = false
        focusSelectionIfNeeded()
    }
    func restorePosition(_ point: CGPoint) {
        let current = primary.contentView.bounds.origin
        if abs(point.x - current.x) > 1 || abs(point.y - current.y) > 1 { pendingPosition = point }
    }
    private func focusSelectionIfNeeded() {
        guard focusIssueID != lastFocusedID else { return }
        lastFocusedID = focusIssueID
        guard let id = focusIssueID, let issue = text.issues.first(where: { $0.id == id }),
              let rect = text.focusRect(for: issue) else { return }
        let scroll = mode == .wipe ? overlay : right
        let target = rect.insetBy(dx: -16, dy: -16)
        if !scroll.documentVisibleRect.contains(target) { text.scrollToVisible(target) }
    }
    @objc private func scrolled(_ note: Notification) {
        guard !syncing, let clip = note.object as? NSClipView else { return }
        if mode == .wipe {
            if clip === overlay.contentView { updateWipe(); onPositionChange?(clip.bounds.origin) }
            return
        }
        guard clip === left.contentView || clip === right.contentView else { return }
        syncing = true
        let other = clip === left.contentView ? right : left
        other.contentView.scroll(to: clip.bounds.origin)
        other.reflectScrolledClipView(other.contentView)
        syncing = false
        onPositionChange?(clip.bounds.origin)
    }
    private func updateWipe() {
        guard mode == .wipe else { return }
        let fraction = min(1, max(0, wipeFraction))
        let visible = overlay.contentView.bounds
        let cut = visible.minX + visible.width * fraction
        wipeCanvas.cut = cut
        let leftMask = CAShapeLayer(), rightMask = CAShapeLayer()
        leftMask.frame = source.bounds; rightMask.frame = text.bounds
        leftMask.path = CGPath(rect: CGRect(x: 0, y: 0, width: cut, height: source.bounds.height), transform: nil)
        rightMask.path = CGPath(rect: CGRect(x: cut, y: 0, width: max(0, text.bounds.width - cut), height: text.bounds.height), transform: nil)
        source.layer?.mask = leftMask; text.layer?.mask = rightMask
        divider.track = NSRect(x: overlay.frame.minX, y: overlay.frame.minY, width: visible.width, height: overlay.frame.height)
        divider.fraction = fraction
        divider.frame = NSRect(x: overlay.frame.minX + visible.width * fraction - 10,
            y: overlay.frame.minY, width: 20, height: overlay.frame.height)
        divider.needsDisplay = true
    }
    @objc private func magnified(_ gesture: NSMagnificationGestureRecognizer) {
        if gesture.state == .began { pinchStart = zoom }
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        let point = gesture.location(in: primary.contentView)
        let anchor = NSPoint(x: point.x - primary.contentView.bounds.minX, y: point.y - primary.contentView.bounds.minY)
        applyZoom(pinchStart * (1 + gesture.magnification), anchor: anchor)
    }
    func applyZoom(_ value: Double, anchor: NSPoint) {
        let next = min(2, max(0.75, value))
        guard abs(next - zoom) > 0.0001 else { return }
        let old = zoom, point = primary.contentView.bounds.origin
        zoom = next; needsLayout = true; layoutSubtreeIfNeeded()
        let ratio = next / old
        let target = NSPoint(x: (point.x + anchor.x) * ratio - anchor.x, y: (point.y + anchor.y) * ratio - anchor.y)
        syncing = true
        for scroll in mode == .wipe ? [overlay] : [left, right] {
            scroll.contentView.scroll(to: target); scroll.reflectScrolledClipView(scroll.contentView)
        }
        syncing = false; updateWipe(); onZoomChange?(next); onPositionChange?(primary.contentView.bounds.origin)
    }
}

private final class WipeCanvasView: NSView {
    weak var source: SourcePageView?
    weak var text: TranscriptPageView?
    var cut: CGFloat = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return local.x < cut ? source?.hitTest(local) : text?.hitTest(local)
    }
}

private final class WipeDividerView: NSView {
    var onChange: ((Double) -> Void)?
    var fraction = 0.5
    var track = NSRect.zero
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.slider); setAccessibilityLabel("对照分界")
    }
    required init?(coder: NSCoder) { nil }
    override func accessibilityValue() -> Any? { Int(fraction * 100) }
    override func accessibilityPerformIncrement() -> Bool { onChange?(min(1, fraction + 0.05)); return true }
    override func accessibilityPerformDecrement() -> Bool { onChange?(max(0, fraction - 0.05)); return true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        WorkspaceStyle.imageFocusColor.setFill()
        NSRect(x: bounds.midX - 1, y: 0, width: 2, height: bounds.height).fill()
        let knob = NSRect(x: 1, y: bounds.midY - 20, width: 18, height: 40)
        NSBezierPath(roundedRect: knob, xRadius: 8, yRadius: 8).fill()
        NSColor.white.setFill()
        NSRect(x: knob.midX - 3, y: knob.midY - 5, width: 1, height: 10).fill()
        NSRect(x: knob.midX + 2, y: knob.midY - 5, width: 1, height: 10).fill()
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); move(event) }
    override func mouseDragged(with event: NSEvent) { move(event) }
    private func move(_ event: NSEvent) {
        guard let parent = superview else { return }
        let point = parent.convert(event.locationInWindow, from: nil)
        onChange?(min(1, max(0, (point.x - track.minX) / max(1, track.width))))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 { _ = accessibilityPerformDecrement() }
        else if event.keyCode == 124 { _ = accessibilityPerformIncrement() }
        else if event.keyCode == 115 { onChange?(0) }
        else if event.keyCode == 119 { onChange?(1) }
        else { super.keyDown(with: event) }
    }
}

final class SourcePageView: NSView {
    var image: NSImage?
    var transcript: Transcript?
    var uncertainLineIDs: [Int] = []
    var selectedIssue: ReviewIssue?
    var issues: [ReviewIssue] = []
    var wordRegions: [WordRegion] = []
    var uncertainWordRects: [PageRect] = []
    var onIssueClick: ((UUID) -> Void)?
    var pageHeight: CGFloat = 0
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        WorkspaceStyle.pageColor.setFill(); bounds.fill()
        let imageHeight = pageHeight > 0 ? pageHeight : bounds.height
        image?.draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: imageHeight), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high])
        // Recognition ambiguity uses word-level purple, separate from red/orange
        // language marks. Stable words receive no recognition decoration.
        for box in uncertainWordRects {
            let rect = pixelRect(box, imageHeight: imageHeight)
            NSColor.systemPurple.withAlphaComponent(0.10).setFill(); rect.insetBy(dx: -2, dy: -2).fill()
            let path = NSBezierPath(); path.move(to: NSPoint(x: rect.minX, y: rect.maxY + 3))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY + 3)); path.setLineDash([2, 3], count: 2, phase: 0)
            NSColor.systemPurple.withAlphaComponent(0.8).setStroke(); path.stroke()
        }
        if let selectedIssue {
            var boxes = wordRegions.filter { word in word.range.map { NSIntersectionRange($0, selectedIssue.range).length > 0 } ?? false }.map(\.rect)
            if boxes.isEmpty, transcript?.isAligned == true {
                boxes = (transcript?.lines ?? []).filter { $0.hasGeometry && NSIntersectionRange($0.range, selectedIssue.range).length > 0 }.map(\.rect)
            }
            for box in boxes {
                let rect = pixelRect(box, imageHeight: imageHeight).insetBy(dx: -3, dy: -3)
                WorkspaceStyle.imageFocusColor.withAlphaComponent(0.08).setFill(); rect.fill()
                WorkspaceStyle.imageFocusColor.setStroke(); NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).stroke()
            }
        }
    }
    private func pixelRect(_ rect: PageRect, imageHeight: CGFloat) -> NSRect {
        NSRect(x: rect.x * bounds.width, y: rect.y * imageHeight, width: rect.width * bounds.width, height: rect.height * imageHeight)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for word in wordRegions where pixelRect(word.rect, imageHeight: pageHeight).insetBy(dx: -3, dy: -3).contains(point) {
            if let range = word.range, let issue = issues.first(where: { NSIntersectionRange($0.range, range).length > 0 }) {
                onIssueClick?(issue.id); return
            }
        }
    }
}

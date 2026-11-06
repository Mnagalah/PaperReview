import AppKit
import SwiftUI
import PaperReviewCore

/// A selectable native text surface; link ranges use the transcript's UTF-16
/// offsets, so soft wrapping never changes the annotation anchors.
struct ReadingDocumentView: NSViewRepresentable {
    let transcript: Transcript?
    let issues: [ReviewIssue]
    let selectedIssueID: UUID?
    let fontSize: Double
    let onSelect: (UUID) -> Void
    let review: TeacherReview?
    var uncertainRanges: [NSRange] = []
    var offset: Double = 0
    var onScroll: (Double) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let text = NSTextView(frame: .zero)
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.isRichText = true; text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 36, height: 28)
        text.linkTextAttributes = [:]; text.delegate = context.coordinator
        text.setAccessibilityLabel("识别稿")
        scroll.documentView = text
        context.coordinator.scroll = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect; coordinator.onScroll = onScroll
        let old = scroll.contentView.bounds.origin
        let value = NSMutableAttributedString(string: transcript?.text ?? "识别完成后，文字会显示在这里。")
        let style = NSMutableParagraphStyle(); style.lineSpacing = fontSize * 0.45; style.paragraphSpacing = 12
        value.addAttributes([.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.textColor,
            .paragraphStyle: style], range: NSRange(location: 0, length: value.length))
        for range in uncertainRanges where range.location >= 0 && NSMaxRange(range) <= value.length {
            value.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: NSColor.systemPurple], range: range)
        }
        if let transcript {
            for issue in issues where issue.revision == transcript.revision && issue.start >= 0 && NSMaxRange(issue.range) <= value.length {
                let selected = issue.id == selectedIssueID
                let color = issue.kind == .spelling ? WorkspaceStyle.spellingColor : WorkspaceStyle.grammarColor
                value.addAttributes([.link: URL(string: "paperreview://issue/\(issue.id.uuidString)")!,
                    ], range: issue.range)
                value.addAttributes(WorkspaceStyle.annotationAttributes(color: selected ? WorkspaceStyle.photoFocusColor : color,
                    light: context.environment.colorScheme == .light,
                    highContrast: context.environment.colorSchemeContrast == .increased), range: issue.range)
                if selected { value.addAttributes([.backgroundColor: WorkspaceStyle.selectionColor.withAlphaComponent(0.6),
                    .foregroundColor: WorkspaceStyle.photoFocusColor], range: issue.range) }
            }
        }
        if let review, let transcript {
            value.append(NSAttributedString(string: "\n\n批注\n", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor]))
            for annotation in review.annotations(in: transcript) {
                value.append(NSAttributedString(string: "\n\(annotation.quote) → \(annotation.suggestion.isEmpty ? "建议删除" : annotation.suggestion)\n\(annotation.explanation)\n",
                    attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.textColor, .paragraphStyle: style]))
            }
            if !review.comment.isEmpty { value.append(NSAttributedString(string: "\n评语\n\(review.comment)", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.textColor])) }
        }
        coordinator.updating = true
        if text.attributedString() != value { text.textStorage?.setAttributedString(value) }
        text.frame.size.width = scroll.contentSize.width
        text.sizeToFit()
        text.frame.size.height = max(text.frame.height, scroll.contentSize.height)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: coordinator.initialized ? old.y : offset))
        scroll.reflectScrolledClipView(scroll.contentView)
        if coordinator.initialized, coordinator.selectedID != selectedIssueID,
           let issue = issues.first(where: { $0.id == selectedIssueID }) {
            text.scrollRangeToVisible(issue.range)
        }
        coordinator.initialized = true; coordinator.selectedID = selectedIssueID; coordinator.updating = false
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var scroll: NSScrollView?
        var onSelect: ((UUID) -> Void)?
        var onScroll: ((Double) -> Void)?
        var initialized = false
        var updating = false
        var selectedID: UUID?
        deinit { NotificationCenter.default.removeObserver(self) }
        @objc func scrolled() { if !updating { onScroll?(Double(scroll?.contentView.bounds.origin.y ?? 0)) } }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, let id = UUID(uuidString: url.lastPathComponent) else { return false }
            onSelect?(id); return true
        }
    }
}

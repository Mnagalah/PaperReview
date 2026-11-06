import AppKit
import SwiftUI

/// SwiftUI has no scroller tint API. Keep AppKit's scrolling, accessibility,
/// hit testing and system overlay/always-visible preference; only draw its parts.
struct ReviewScrollAppearance: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.light = colorScheme == .light
        view.install()
    }
    final class Anchor: NSView {
        var light = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); install() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); install() }
        func install() {
            guard let scroll = enclosingScrollView, let previous = scroll.verticalScroller else { return }
            let scroller: ReviewScroller
            if let existing = previous as? ReviewScroller { scroller = existing }
            else {
                scroller = ReviewScroller(frame: previous.frame)
                scroller.controlSize = previous.controlSize
                scroller.scrollerStyle = previous.scrollerStyle
                scroller.knobStyle = previous.knobStyle
                scroller.target = previous.target; scroller.action = previous.action
                scroller.doubleValue = previous.doubleValue; scroller.knobProportion = previous.knobProportion
                scroll.verticalScroller = scroller
            }
            scroller.light = light; scroller.needsDisplay = true
        }
    }
}

final class ReviewScroller: NSScroller {
    var light = false
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnob() {
        guard light, !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else { super.drawKnob(); return }
        let rect = rect(for: .knob).insetBy(dx: 2, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }
        WorkspaceStyle.scrollerColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
    }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        if !light || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            super.drawKnobSlot(in: slotRect, highlight: flag)
        }
    }
}

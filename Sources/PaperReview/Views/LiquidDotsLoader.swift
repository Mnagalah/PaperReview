import SwiftUI

/// Native rendering of the two merging dots in the user's Amicro reference:
/// https://amicro.dev/loaders/liquid-dots . No web view or animation dependency.
struct LiquidDotsLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30,
            paused: reduceMotion || scenePhase != .active)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(started)
            LiquidDotsFrame(separation: reduceMotion ? 11 : Self.separation(at: elapsed),
                color: colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.7))
        }
        .frame(width: 72, height: 36)
        .accessibilityHidden(true) // The adjacent phase text announces the operation.
    }

    /// A 1.6-second continuous cycle; velocity is zero at merge and separation.
    static func separation(at elapsed: TimeInterval) -> Double {
        7 * (1 - cos(2 * .pi * elapsed / 1.6))
    }
}

struct LiquidDotsFrame: View {
    let separation: Double
    var color: Color = .primary

    var body: some View {
        Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.45, color: color))
            context.addFilter(.blur(radius: 3))
            context.drawLayer { layer in
                for direction in [-1.0, 1.0] {
                    let center = CGPoint(x: size.width / 2 + direction * separation, y: size.height / 2)
                    layer.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.white))
                }
            }
        }
    }
}

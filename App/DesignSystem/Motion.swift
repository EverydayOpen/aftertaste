import AftertasteCore
import SwiftUI

// docs/MOTION.md §1.8 and §3: the pointer tilt, the card flip, and which rows have left. macOS 13 APIs only.

/// Turns a surface to face the pointer (the edge under it recedes), at most `max` degrees, with an optional glare
/// masked to the content's own shape. Flat under Reduce Motion or with `max: 0`. The pointer is read in the layout
/// frame, so the tilt never moves hit areas. Used on exactly three views (MOTION §3.5): the welcome drop zone, the
/// first-run icon, the card preview. Never on rows, group cards or bars.
struct HoverTilt: ViewModifier {
    var max = 7.0
    var glare = false
    @State private var size = CGSize.zero
    @State private var p = CGPoint.zero          // -1...1 from the center
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if glare && hovering {
                    RadialGradient(colors: [Color.white.opacity(0.28), .clear], center: .center,
                                   startRadius: 0, endRadius: size.width * 0.6)
                        .offset(x: p.x * size.width / 2, y: p.y * size.height / 2)
                        .mask { content }            // VERIFY: content drawn twice; fine for an icon and one card
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // VERIFY on a Mac: the edge under the pointer should recede; negate both angles if it rises instead.
            .rotation3DEffect(.degrees(-p.y * max), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(p.x * max), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .background {
                GeometryReader { g in
                    Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = $0 }
                }
            }
            .onContinuousHover { phase in
                guard !reduceMotion, max > 0, size.width > 0, size.height > 0 else { return }
                switch phase {
                case .active(let at):
                    withAnimation(Motion.follow) {
                        hovering = true
                        p = CGPoint(x: at.x / size.width * 2 - 1, y: at.y / size.height * 2 - 1)
                    }
                case .ended:
                    withAnimation(Motion.spring(false)) {
                        hovering = false
                        p = .zero
                    }
                }
            }
    }
}

extension AnyTransition {
    /// A group card arriving (MOTION §3.4): turns down into place from the top edge like a split-flap card, and leaves
    /// by fading, so old and new never overlap mid-turn. Opacity only under Reduce Motion.
    static func flip(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .modifier(active: FlipDown(angle: 70, opacity: 0), identity: FlipDown(angle: 0, opacity: 1)),
            removal: .opacity)
    }
}

private struct FlipDown: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content   // VERIFY sign on a Mac: the bottom edge should start toward the viewer
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .opacity(opacity)
    }
}

/// Shows the content until the turn passes 90°, then `back`: a card turning over. `angle` animates. The Trace Report
/// preview is dealt once with `FlipFaces(angle: dealt ? 0 : 180, back: CardBack())` (MOTION §3.3).
struct FlipFaces<Back: View>: ViewModifier, Animatable {
    var angle: Double
    let back: Back
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(angle < 90 ? 1 : 0)
            .overlay {
                back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(angle < 90 ? 0 : 1)
                    .accessibilityHidden(true)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

/// A row leaves when its outcome has been reported as moved. Rows whose outcome is anything else stay, and the result
/// sheet says why. Honest timing: rows leave as outcomes arrive, never on a fake schedule (MOTION §3.2).
func departed(_ plan: TrashPlan, finished: Int, moved: (String) -> Bool) -> Set<String> {
    Set(plan.items.prefix(finished).map(\.id).filter(moved))
}

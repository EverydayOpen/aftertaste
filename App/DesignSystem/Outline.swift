import SwiftUI

// docs/DESIGN.md §6.3 and docs/MOTION.md §3.2: the signature object and the one signature animation.

/// The dashed violet stroke of a box: the after-image a moved row leaves, and the edge of the welcome drop zone.
/// Static; pass `opacity` to fade it.
struct DashedOutline: View {
    var radius: CGFloat = Radius.row
    var lineWidth: CGFloat = 1.5
    var opacity = 0.7

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Brand.duskInk, style: StrokeStyle(lineWidth: lineWidth, dash: [5, 4]))
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The after-image a moved row leaves: its content fades fast, a dashed violet outline of its box stays for a moment,
/// then the outline fades too. One animatable `progress` (0 = the row, 1 = gone) drives both, so a transition can run
/// it. Pure fills and strokes: ImageRenderer-safe, nothing loops.
struct Outline: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let fade = max(0, 1 - progress * 3.3)                                                // content gone by 30 %
        let trace = progress < 0.3 ? progress / 0.3 : max(0, 1 - (progress - 0.3) / 0.7)      // rises, then fades by 100 %
        content
            .opacity(fade)
            .overlay { DashedOutline(opacity: trace * 0.7) }
    }
}

extension AnyTransition {
    /// A row leaving for the Trash (MOTION §3.2), `index` rows into the list: the staggered delay is part of it. Opacity
    /// only under Reduce Motion, in 150 ms with no delay.
    static func outline(_ reduceMotion: Bool, index: Int = 0) -> AnyTransition {
        let leaving: AnyTransition = reduceMotion ? .opacity : .modifier(active: Outline(progress: 1), identity: Outline(progress: 0))
        // Only leaving: rows that appear with a scan result come in plain.
        return AnyTransition.asymmetric(insertion: .identity, removal: leaving)
            .animation(Motion.spring(reduceMotion).delay(Motion.delay(index, reduceMotion)))
    }
}

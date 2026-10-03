import SwiftUI

// docs/DESIGN.md §6.1: the one prominent button, the key-cap choices, and the copy button.

/// The one prominent button per screen (Move 14 items to Trash, Undo all, Continue): a dusk key-cap with near-black
/// text, a lit top edge and a violet-black lip; a press sinks 1pt. No glow: the light comes from the horizon, not the
/// button. `.keyboardShortcut(.defaultAction)` still works. Replaces .borderedProminent there.
struct DuskButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Plate(configuration: configuration) }

    // Not `Body`: that is ButtonStyle's associated type.
    private struct Plate: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let down = configuration.isPressed && !reduceMotion
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.onDusk)
                .padding(.horizontal, 18)
                .frame(minHeight: 30)
                .background(shape.fill(Brand.dusk).overlay(shape.fill(LinearGradient(colors: [.clear, Color.black.opacity(0.12)], startPoint: .top, endPoint: .bottom))))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.black.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .background(shape.fill(Color(red: 0.30, green: 0.23, blue: 0.62)).offset(y: down ? 0.5 : 1.5))   // the lip; its bottom stays put
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.4)
                .offset(y: down ? 1 : 0)
                .animation(Motion.pop, value: configuration.isPressed)
        }
    }
}

/// A real key-cap (Welcome choices): a face lighter at the top with a lit rim, on a side wall that shrinks from 3pt to
/// 1pt as the face sinks 2pt. The rim turns violet under the pointer (a colour, not motion). No tilt: HoverTilt is used
/// on exactly three views (MOTION §3.5). The label is padded by `Space.m`.
struct KeyCapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Cap(configuration: configuration) }

    private struct Cap: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            let dark = scheme == .dark, down = configuration.isPressed && !reduceMotion
            let face = dark ? [Color(red: 0.149, green: 0.169, blue: 0.220), Color(red: 0.098, green: 0.114, blue: 0.157)]   // #262B38 → #191D28
                            : [Color.white, Color(red: 0.945, green: 0.941, blue: 0.973)]                                        // #FFFFFF → #F1F0F8
            let wall = dark ? Color(red: 0.027, green: 0.031, blue: 0.047) : Color(red: 0.812, green: 0.796, blue: 0.878)        // #07080C / #CFCBE0
            configuration.label
                .frame(maxWidth: .infinity)
                .padding(Space.m)
                .background {
                    if contrast == .increased {
                        shape.fill(.quaternary).overlay(shape.strokeBorder(Color.primary, lineWidth: 1))
                    } else {
                        ZStack {
                            // The side wall. In dark its rim keeps it apart from the near-black desk.
                            shape.fill(wall).overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.10 : 0), lineWidth: 1)).offset(y: down ? 1 : 3)
                            shape.fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                                .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.14 : 0.9), lineWidth: 1)
                                    .mask { LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center) })   // the lit top rim
                                .overlay(shape.strokeBorder(hovering && enabled ? Brand.dusk.opacity(0.7) : Color.primary.opacity(dark ? 0.08 : 0.12), lineWidth: hovering && enabled ? 1 : 0.5))
                                .shadow(color: Brand.ink.opacity(dark ? 0.5 : 0.10), radius: 8, y: 4)   // constant: never animated
                        }
                    }
                }
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.5)
                .offset(y: down ? 2 : 0)
                .animation(Motion.pop, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// Copying has no visible effect, so the title reads "Copied" for a moment.
struct CopyButton: View {
    var title = "Copy"
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : title) {
            action()
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copied = false
            }
        }
    }
}
